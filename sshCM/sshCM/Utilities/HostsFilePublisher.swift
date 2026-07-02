import Foundation
import Darwin
import AppKit

/// Keeps an app-owned block in `/etc/hosts` in sync with the user's SSH hosts so
/// that aliases resolve system-wide (Screen Sharing, VNC, browsers, …), not just
/// inside `ssh`. Only hosts whose `HostName` is a literal IP are published — a
/// DNS name already resolves, and there is no single address to map otherwise.
///
/// Writing `/etc/hosts` requires root, so changes are applied through a single
/// admin-authentication prompt (`osascript … with administrator privileges`).
/// To avoid prompting needlessly, a sync that wouldn't change the managed block
/// is skipped entirely (no prompt).
///
/// Pure block-computation helpers live in `HostsFileBlock` (Models/) so they can
/// be tested without AppKit or elevated privileges.
enum HostsFilePublisher {
    static let defaultsKey = AppStorageKey.publishAliasesToHostsFile.rawValue
    static let hostsPath = "/etc/hosts"

    enum SyncResult: Equatable {
        /// The managed block already matched — no write, no prompt.
        case unchanged
        /// `/etc/hosts` was updated.
        case updated
        /// The user dismissed the admin-authentication dialog.
        case cancelled
        /// The write failed.
        case failed(String)
    }

    // MARK: - Public API

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    /// Brings `/etc/hosts` in line with `hosts`, prompting for admin rights only
    /// if the managed block actually changes.
    @discardableResult
    static func sync(hosts: [SSHHost]) async -> SyncResult {
        guard let newContent = plannedContent(for: hosts) else { return .unchanged }
        return await applyElevated(content: newContent)
    }

    /// Removes the managed block entirely (used when the user opts out).
    /// Prompts for admin rights only if a block is actually present.
    @discardableResult
    static func clear() async -> SyncResult {
        await sync(hosts: [])
    }

    /// The full `/etc/hosts` text after replacing the managed block, or `nil`
    /// when it would be identical to what's already on disk.
    static func plannedContent(for hosts: [SSHHost]) -> String? {
        let current = (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
        let rebuilt = HostsFileBlock.rebuild(
            current: current,
            entries: HostsFileBlock.managedEntries(for: hosts)
        )
        return rebuilt == current ? nil : rebuilt
    }

    // MARK: - Privileged write

    private static func applyElevated(content: String) async -> SyncResult {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshCM-hosts-\(UUID().uuidString)")
        do {
            try content.write(to: tmp, atomically: true, encoding: .utf8)
        } catch {
            return .failed("Could not stage the hosts file: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        // The admin-authentication prompt (Touch ID's SecurityAgent or the
        // osascript dialog) is presented by another process and steals focus.
        // When it's dismissed, macOS may leave that process frontmost instead of
        // returning to us, pushing our window behind. Note whether we were the
        // active app before the prompt so we can reclaim focus afterward.
        let wasActive = await MainActor.run { NSApp.isActive }

        // Install atomically, restore canonical ownership/permissions, then nudge
        // the resolver caches. The cache flush is best-effort (`; … || true`).
        let shell = "/bin/cp '\(tmp.path)' /etc/hosts"
            + " && /bin/chmod 644 /etc/hosts"
            + " && /usr/sbin/chown root:wheel /etc/hosts"
            + "; /usr/bin/dscacheutil -flushcache 2>/dev/null"
            + "; /usr/bin/killall -HUP mDNSResponder 2>/dev/null; true"

        // Prefer `sudo` when the user has Touch ID for sudo configured
        // (`pam_tid.so`), so they can authenticate with a fingerprint instead of
        // typing a password. `sudo` falls back to a TTY password prompt when
        // biometric auth is unavailable, which a GUI process can't satisfy — so
        // on any sudo failure we fall back to the classic AppleScript admin
        // dialog, which everyone (Touch ID or not) can complete.
        let result: SyncResult
        if touchIDSudoConfigured() {
            let sudoResult = await runViaSudo(shell: shell)
            switch sudoResult {
            case .updated, .cancelled:
                result = sudoResult
            case .unchanged, .failed:
                result = await runViaOSAScript(shell: shell)
            }
        } else {
            result = await runViaOSAScript(shell: shell)
        }

        // Reclaim focus if the prompt left another app frontmost.
        if wasActive {
            await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
        }
        return result
    }

    /// Runs the privileged shell via `sudo`. With `pam_tid.so` configured this
    /// surfaces a Touch ID prompt and needs no TTY. stdin is detached so that if
    /// biometric auth is unavailable `sudo` fails fast (EOF) rather than hanging
    /// waiting for a password it can never receive.
    private static func runViaSudo(shell: String) async -> SyncResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            // `-p ""` suppresses the text prompt; `-k` is not used so a recently
            // cached sudo credential can still authorize without re-prompting.
            process.arguments = ["-p", "", "/bin/sh", "-c", shell]
            process.standardInput = FileHandle.nullDevice
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                return SyncResult.failed(error.localizedDescription)
            }
            process.waitUntilExit()
            if process.terminationStatus == 0 { return .updated }
            let message = readTrimmed(errPipe)
            // pam_tid surfaces an explicit biometric cancel; honor it rather than
            // falling through to a second (password) prompt.
            if message.localizedCaseInsensitiveContains("cancel") {
                return .cancelled
            }
            return .failed(message.isEmpty ? "sudo authorization failed." : message)
        }.value
    }

    /// Classic elevation via the system admin-authentication dialog. Works for
    /// every user and is the fallback when `sudo`/Touch ID isn't usable.
    private static func runViaOSAScript(shell: String) async -> SyncResult {
        // `shell` is embedded in an AppleScript double-quoted string literal, so
        // any backslash or double-quote in it must be escaped or the script is
        // malformed (and, in principle, injectable). Today the only variable is a
        // UUID temp path, but escape defensively rather than rely on that.
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                return SyncResult.failed(error.localizedDescription)
            }
            process.waitUntilExit()
            if process.terminationStatus == 0 { return .updated }
            let message = readTrimmed(errPipe)
            // osascript reports a user-dismissed auth dialog as error -128.
            if message.contains("User canceled") || message.contains("-128") {
                return .cancelled
            }
            return .failed(message.isEmpty ? "Authorization failed." : message)
        }.value
    }

    /// Whether `sudo` is set up to accept Touch ID (`pam_tid.so`). Checks the
    /// recommended `sudo_local` drop-in first, then the main `sudo` PAM file.
    /// Read-only; ignores commented-out lines.
    static func touchIDSudoConfigured() -> Bool {
        for path in ["/etc/pam.d/sudo_local", "/etc/pam.d/sudo"] {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for rawLine in text.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") { continue }
                if line.contains("pam_tid.so") { return true }
            }
        }
        return false
    }

    private static func readTrimmed(_ pipe: Pipe) -> String {
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
