import Foundation

/// Detects whether a host would let you in on key authentication alone, so
/// hosts still relying on password auth can be flagged with a one-click
/// "Set Up Key Authentication" action.
///
/// This runs a genuine SSH connection attempt — unlike `Reachability`'s bare
/// TCP probe or `HostKeyVerifier`'s unauthenticated keyscan, this actually
/// negotiates authentication. `BatchMode=yes` is what makes it safe to run
/// unattended: it disables every interactive prompt ssh could otherwise show
/// (password, keyboard-interactive, "are you sure you want to continue
/// connecting?" for an unknown/changed host key), so the attempt can only
/// ever succeed or fail fast — it can never block on user input, leak a
/// password, or silently accept a host key. A host whose key hasn't been
/// verified yet, or has changed, will simply fail this check (reported as
/// "needs setup") rather than prompting; that's a conservative label, never a
/// bypass of the host-key security model.
enum KeyAuthChecker {
    nonisolated private static let sshPath = "/usr/bin/ssh"

    /// - Parameters:
    ///   - alias: the `Host` alias to connect to, so `~/.ssh/config`'s
    ///     `User`/`IdentityFile`/`ProxyJump`/etc. apply exactly as they would
    ///     for a real connection.
    ///   - timeout: bounds the TCP connect phase (`ConnectTimeout`); the whole
    ///     attempt is additionally hard-capped a few seconds past that in case
    ///     the server accepts the connection but stalls during negotiation.
    static func check(alias: String, timeout: Int = 6) async -> Bool {
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else { return false }
        return await Task.detached(priority: .utility) {
            run(alias: trimmed, timeout: timeout)
        }.value
    }

    nonisolated private static func run(alias: String, timeout: Int) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: sshPath) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "PasswordAuthentication=no",
            "-o", "KbdInteractiveAuthentication=no",
            "-o", "ConnectTimeout=\(timeout)",
            "-o", "ConnectionAttempts=1",
            alias, "exit"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(TimeInterval(timeout) + 3)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return false
        }
        return process.terminationStatus == 0
    }
}
