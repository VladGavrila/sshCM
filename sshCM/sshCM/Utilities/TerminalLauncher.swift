import AppKit
import Foundation

enum TerminalLauncher {
    static let defaultTerminalAppPath = "/System/Applications/Utilities/Terminal.app"

    /// When true (the default), the launch script drops into an interactive
    /// login shell after `ssh` exits so the tab stays open for review instead
    /// of closing on logout/reset.
    static let keepSessionOpenKey = "keepTerminalOpenAfterSession"

    private static var keepSessionOpen: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keepSessionOpenKey) != nil else { return true }
        return defaults.bool(forKey: keepSessionOpenKey)
    }

    static func launchSSH(
        toAlias alias: String,
        user: String? = nil,
        bypassHostKey: Bool = false,
        terminalAppPath: String
    ) throws {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }

        let escapedAlias = trimmedAlias.replacingOccurrences(of: "'", with: "'\\''")
        var userArg = ""
        if let user, !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escapedUser = user
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "'", with: "'\\''")
            userArg = " -l '\(escapedUser)'"
        }

        // One-off bypass of strict host-key checking. Sending known hosts to
        // /dev/null also avoids re-recording the (possibly malicious) key.
        let bypassArgs = bypassHostKey
            ? " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            : ""

        let sshCommand = "ssh\(userArg)\(bypassArgs) '\(escapedAlias)'"
        let body: String
        if keepSessionOpen {
            body = """
            clear
            \(sshCommand)
            echo '[sshCM] Session ended — returning to shell.'
            exec "$SHELL" -l
            """
        } else {
            body = "clear\nexec \(sshCommand)"
        }
        try runScript(body, terminalAppPath: terminalAppPath)
    }

    static func launchCommand(_ command: String, terminalAppPath: String) throws {
        try runScript("clear\n\(command)", terminalAppPath: terminalAppPath)
    }

    private static func runScript(_ body: String, terminalAppPath: String) throws {
        let scriptURL = try writeTempScript(body: body)
        let resolvedAppPath = terminalAppPath.isEmpty ? defaultTerminalAppPath : terminalAppPath
        let appURL = URL(fileURLWithPath: resolvedAppPath)

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw TerminalLaunchError.terminalAppNotFound(resolvedAppPath)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(
            [scriptURL],
            withApplicationAt: appURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("TerminalLauncher failed: \(error.localizedDescription)")
            }
        }
    }

    private static func writeTempScript(body: String) throws -> URL {
        let script = """
        #!/bin/bash
        \(body)
        """

        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("sshcm-\(UUID().uuidString).command")
        try script.data(using: .utf8)?.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }
}

enum TerminalLaunchError: LocalizedError {
    case invalidAlias
    case terminalAppNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidAlias:
            return "Host alias is empty."
        case .terminalAppNotFound(let path):
            return "Terminal application not found at \(path)."
        }
    }
}
