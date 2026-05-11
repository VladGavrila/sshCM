import AppKit
import Foundation

enum TerminalLauncher {
    static let defaultTerminalAppPath = "/System/Applications/Utilities/Terminal.app"

    static func launchSSH(toAlias alias: String, terminalAppPath: String) throws {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }

        let escaped = trimmedAlias.replacingOccurrences(of: "'", with: "'\\''")
        try runScript("clear\nexec ssh '\(escaped)'", terminalAppPath: terminalAppPath)
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
