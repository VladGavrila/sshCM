import Foundation
import AppKit

enum InstallError: LocalizedError {
    case extractionFailed(String)
    case appNotFound
    case bundleIDMismatch(expected: String, found: String?)
    case notWritable(path: String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Could not extract update archive: \(msg)"
        case .appNotFound: return "Update archive did not contain an app bundle."
        case .bundleIDMismatch(let expected, let found):
            return "Update bundle ID mismatch (expected \(expected), got \(found ?? "?"))."
        case .notWritable(let path):
            return "Cannot replace app at \(path). Move sshCM.app to a writable location and try again."
        case .scriptFailed(let msg): return "Installer script failed: \(msg)"
        }
    }
}

enum AppInstaller {
    /// The Developer ID team that legitimately signs sshCM releases (matches
    /// `DEVELOPMENT_TEAM` in the project and `TEAM_ID` in `build-release.sh`).
    /// The update's signer is pinned to this, so a merely *validly*-signed (e.g.
    /// ad-hoc) bundle from a hijacked release doesn't pass — only one signed by
    /// us does.
    static let expectedTeamID = "2RZL73M634"

    /// Extracts and validates the update **without** stripping quarantine or
    /// touching the installed app. Throws only on hard failures (bad archive,
    /// no app bundle, wrong bundle id). A missing/foreign Developer ID signature
    /// is reported via `PreparedInstall.signatureVerified`, not thrown — so the
    /// caller can offer an explicit opt-in rather than silently trusting it.
    ///
    /// Runs off the main actor: `ditto`/`codesign` on a whole app bundle can take
    /// a moment, and this is called from `UpdateChecker`, which is `@MainActor`.
    static func verifyAndPrepare(zipURL: URL, expectedBundleID: String) async throws -> PreparedInstall {
        try await Task.detached(priority: .utility) {
            try verifyAndPrepareSync(zipURL: zipURL, expectedBundleID: expectedBundleID)
        }.value
    }

    /// Swaps the verified (or user-accepted) update in for the running app and
    /// relaunches. Quarantine is stripped only here — after all checks and any
    /// opt-in — so an un-vetted bundle is never de-quarantined. The subprocess
    /// work runs off the main actor; only the final termination is hopped back
    /// to it, since `NSApplication` is main-actor-isolated.
    static func commitInstall(_ prepared: PreparedInstall) async throws {
        try await Task.detached(priority: .utility) {
            try commitInstallSync(prepared)
        }.value
        await MainActor.run {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private static func verifyAndPrepareSync(zipURL: URL, expectedBundleID: String) throws -> PreparedInstall {
        let workDir = zipURL.deletingLastPathComponent().appendingPathComponent("extracted", isDirectory: true)
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, workDir.path])
            .throwing(InstallError.extractionFailed)

        guard let newApp = try findApp(in: workDir) else {
            throw InstallError.appNotFound
        }

        let infoURL = newApp.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any]
        let foundID = info?["CFBundleIdentifier"] as? String
        guard foundID == expectedBundleID else {
            throw InstallError.bundleIDMismatch(expected: expectedBundleID, found: foundID)
        }

        // Pin the signer BEFORE any quarantine strip, so we don't defeat
        // Gatekeeper's own assessment by un-quarantining first. `-R` tests the
        // (already-signed) bundle against a designated requirement rather than
        // just "is it signed at all".
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\""
        let verify = runProcess(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "-R=\(requirement)", newApp.path]
        )
        return PreparedInstall(newApp: newApp, zipURL: zipURL, signatureVerified: verify.exitCode == 0)
    }

    private static func commitInstallSync(_ prepared: PreparedInstall) throws {
        let newApp = prepared.newApp
        _ = runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        let currentApp = Bundle.main.bundleURL
        let parent = currentApp.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) {
            throw InstallError.notWritable(path: currentApp.path)
        }

        let scriptURL = prepared.zipURL.deletingLastPathComponent().appendingPathComponent("install.sh")
        try installerScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Tell the script whether to re-verify after the swap: skip it when the
        // user knowingly accepted an unsigned build, or the re-verify would roll
        // that build straight back and defeat the opt-in.
        let reverify = prepared.signatureVerified ? "1" : "0"
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, String(pid), currentApp.path, newApp.path, reverify]
        process.standardInput = nil
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
        } catch {
            throw InstallError.scriptFailed(error.localizedDescription)
        }
    }

    private static func findApp(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if let direct = contents.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        for entry in contents {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir, let nested = try findApp(in: entry) {
                return nested
            }
        }
        return nil
    }

    // Swaps the bundle atomically-ish: move the old app aside first, install the
    // new one, and roll the old one back if anything fails — so a failed `mv`
    // (cross-volume, permissions, temp dir GC'd) can never leave the user with
    // no app at all. `$4` = "1" re-verifies the swapped-in bundle (skipped for a
    // user-accepted unsigned build). No `set -e`: the rollback paths must run.
    private static let installerScript = """
    #!/bin/bash
    PID="$1"
    OLD="$2"
    NEW="$3"
    VERIFY="$4"
    LOG="${TMPDIR:-/tmp}/sshCM-installer.log"
    exec >>"$LOG" 2>&1
    echo "[$(date)] waiting for pid $PID"
    for i in $(seq 1 60); do
        if ! kill -0 "$PID" 2>/dev/null; then break; fi
        sleep 0.5
    done
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
    sleep 0.5

    BACKUP="${OLD}.sshcm-old"
    rm -rf "$BACKUP"
    echo "[$(date)] moving $OLD aside to $BACKUP"
    if ! mv "$OLD" "$BACKUP"; then
        echo "[$(date)] ERROR: could not move old app aside; relaunching it"
        open "$OLD" 2>/dev/null || true
        exit 1
    fi

    echo "[$(date)] installing $NEW -> $OLD"
    if mv "$NEW" "$OLD"; then
        if [ "$VERIFY" = "1" ] && ! codesign --verify --deep --strict "$OLD" 2>/dev/null; then
            echo "[$(date)] ERROR: post-install verification failed; rolling back"
            rm -rf "$OLD"
            mv "$BACKUP" "$OLD"
            open "$OLD"
            exit 1
        fi
        rm -rf "$BACKUP"
        echo "[$(date)] launching $OLD"
        open "$OLD"
    else
        echo "[$(date)] ERROR: install move failed; restoring backup"
        mv "$BACKUP" "$OLD"
        open "$OLD"
        exit 1
    fi
    """
}

private struct ProcessResult {
    let exitCode: Int32
    let stderr: String

    func throwing(_ make: (String) -> Error) throws {
        if exitCode != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw make(msg.isEmpty ? "exit code \(exitCode)" : msg)
        }
    }
}

@discardableResult
private func runProcess(_ path: String, _ args: [String]) -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let errPipe = Pipe()
    process.standardError = errPipe
    process.standardOutput = Pipe()
    do {
        try process.run()
    } catch {
        return ProcessResult(exitCode: -1, stderr: error.localizedDescription)
    }
    process.waitUntilExit()
    let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
    return ProcessResult(
        exitCode: process.terminationStatus,
        stderr: String(data: errData, encoding: .utf8) ?? ""
    )
}

/// Live `UpdateInstalling` backed by `AppInstaller`. Injected into
/// `UpdateChecker` by the app; tests substitute a fake instead.
struct LiveUpdateInstaller: UpdateInstalling {
    func verifyAndPrepare(zipURL: URL, expectedBundleID: String) async throws -> PreparedInstall {
        try await AppInstaller.verifyAndPrepare(zipURL: zipURL, expectedBundleID: expectedBundleID)
    }
    func commitInstall(_ prepared: PreparedInstall) async throws {
        try await AppInstaller.commitInstall(prepared)
    }
}
