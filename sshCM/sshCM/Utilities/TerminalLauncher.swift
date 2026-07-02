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
        localForwards: [String] = [],
        remoteForwards: [String] = [],
        terminalAppPath: String
    ) throws {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }

        // A leading `-` would make ssh read the alias as an option rather than a
        // destination (e.g. `-oProxyCommand=…` → command execution). Single-quote
        // escaping stops *shell* injection but not ssh argument injection, so
        // reject dash-leading values outright — a real Host alias never starts
        // with one (the add/edit form already forbids it; imports may not).
        guard !trimmedAlias.hasPrefix("-") else {
            throw TerminalLaunchError.invalidAlias
        }

        let escapedAlias = trimmedAlias.replacingOccurrences(of: "'", with: "'\\''")
        var userArg = ""
        if let user, !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUser.hasPrefix("-") else {
                throw TerminalLaunchError.invalidUser
            }
            let escapedUser = trimmedUser.replacingOccurrences(of: "'", with: "'\\''")
            userArg = " -l '\(escapedUser)'"
        }

        // One-off bypass of strict host-key checking. Sending known hosts to
        // /dev/null also avoids re-recording the (possibly malicious) key.
        let bypassArgs = bypassHostKey
            ? " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            : ""

        // On-demand port forwarding. Only the spec is passed; any user-facing
        // note lives in the config metadata and never reaches the command line.
        func forwardArgs(_ specs: [String], flag: String) -> String {
            specs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { " \(flag) '\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
                .joined()
        }
        let tunnelArgs = forwardArgs(localForwards, flag: "-L")
            + forwardArgs(remoteForwards, flag: "-R")

        let sshCommand = "ssh\(userArg)\(bypassArgs)\(tunnelArgs) '\(escapedAlias)'"
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
        sweepStaleScripts()

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

    /// Removes leftover one-shot launch scripts from previous sessions. Each
    /// launch writes a `sshcm-<uuid>.command` that `open` consumes but never
    /// deletes, so without this they pile up in the temp dir until reboot. Only
    /// scripts older than an hour are swept, so one about to be opened is safe.
    private static func sweepStaleScripts() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for url in entries
        where url.lastPathComponent.hasPrefix("sshcm-") && url.pathExtension == "command" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: url) }
        }
    }
}

enum TerminalLaunchError: LocalizedError {
    case invalidAlias
    case invalidUser
    case terminalAppNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidAlias:
            return "Host alias is empty or starts with “-”."
        case .invalidUser:
            return "User name can't start with “-”."
        case .terminalAppNotFound(let path):
            return "Terminal application not found at \(path)."
        }
    }
}
