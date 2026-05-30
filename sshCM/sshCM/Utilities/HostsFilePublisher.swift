import Foundation
import Darwin

/// Keeps an app-owned block in `/etc/hosts` in sync with the user's SSH hosts so
/// that aliases resolve system-wide (Screen Sharing, VNC, browsers, …), not just
/// inside `ssh`. Only hosts whose `HostName` is a literal IP are published — a
/// DNS name already resolves, and there is no single address to map otherwise.
///
/// Writing `/etc/hosts` requires root, so changes are applied through a single
/// admin-authentication prompt (`osascript … with administrator privileges`).
/// To avoid prompting needlessly, a sync that wouldn't change the managed block
/// is skipped entirely (no prompt).
enum HostsFilePublisher {
    /// Whether alias publishing is enabled. Mirrored as an `@AppStorage` toggle
    /// in Settings.
    static let defaultsKey = "publishAliasesToHostsFile"

    static let hostsPath = "/etc/hosts"
    private static let beginMarkerPrefix = "# BEGIN sshCM-managed"
    private static let endMarkerPrefix = "# END sshCM-managed"
    private static let beginMarker =
        "# BEGIN sshCM-managed — do not edit (managed by sshCM; changes here are overwritten)"
    private static let endMarker = "# END sshCM-managed"

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

    // MARK: - Block computation (pure / testable)

    /// One `IP<tab>alias…` line per publishable host. Aliases that are SSH
    /// patterns (`*`, `?`) or otherwise invalid as hostnames are dropped, and a
    /// given alias is only published once (first host wins).
    static func managedEntries(for hosts: [SSHHost]) -> [String] {
        var claimed = Set<String>()
        var lines: [String] = []
        for host in hosts {
            guard let ip = host.hostName?.trimmingCharacters(in: .whitespaces),
                  isLiteralIP(ip) else { continue }
            let names = host.aliases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { isPublishableHostname($0) && !claimed.contains($0) }
            guard !names.isEmpty else { continue }
            names.forEach { claimed.insert($0) }
            lines.append("\(ip)\t\(names.joined(separator: " "))")
        }
        return lines
    }

    /// The full `/etc/hosts` text after replacing the managed block, or `nil`
    /// when it would be identical to what's already on disk.
    static func plannedContent(for hosts: [SSHHost]) -> String? {
        let current = (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
        let rebuilt = rebuild(current: current, entries: managedEntries(for: hosts))
        return rebuilt == current ? nil : rebuilt
    }

    /// Replaces (or removes) the managed block within `current`, leaving all
    /// other lines untouched.
    private static func rebuild(current: String, entries: [String]) -> String {
        var lines = current.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.hasPrefix(beginMarkerPrefix) }),
           let end = lines[start...].firstIndex(where: { $0.hasPrefix(endMarkerPrefix) }) {
            lines.removeSubrange(start...end)
            // Collapse the blank line that used to separate the block.
            if start < lines.count, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: start)
            }
        }

        var base = lines.joined(separator: "\n")
        while base.hasSuffix("\n") || base.hasSuffix(" ") || base.hasSuffix("\t") {
            base.removeLast()
        }

        guard !entries.isEmpty else {
            return base.isEmpty ? "" : base + "\n"
        }
        let block = ([beginMarker] + entries + [endMarker]).joined(separator: "\n")
        return base.isEmpty ? block + "\n" : base + "\n\n" + block + "\n"
    }

    // MARK: - Validation

    static func isLiteralIP(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.withCString { cstr in
            var v4 = in_addr()
            if inet_pton(AF_INET, cstr, &v4) == 1 { return true }
            var v6 = in6_addr()
            return inet_pton(AF_INET6, cstr, &v6) == 1
        }
    }

    /// A hostname safe to write into `/etc/hosts`: non-empty, no whitespace, no
    /// SSH glob/negation characters, only DNS-label characters.
    static func isPublishableHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253 else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
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

        // Install atomically, restore canonical ownership/permissions, then nudge
        // the resolver caches. The cache flush is best-effort (`; … || true`).
        let shell = "/bin/cp '\(tmp.path)' /etc/hosts"
            + " && /bin/chmod 644 /etc/hosts"
            + " && /usr/sbin/chown root:wheel /etc/hosts"
            + "; /usr/bin/dscacheutil -flushcache 2>/dev/null"
            + "; /usr/bin/killall -HUP mDNSResponder 2>/dev/null; true"
        let appleScript = "do shell script \"\(shell)\" with administrator privileges"

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
            let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            let message = (String(data: errData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // osascript reports a user-dismissed auth dialog as error -128.
            if message.contains("User canceled") || message.contains("-128") {
                return .cancelled
            }
            return .failed(message.isEmpty ? "Authorization failed." : message)
        }.value
    }
}
