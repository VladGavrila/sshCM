import AppKit
import Foundation

enum TerminalLauncher {
    static let defaultTerminalAppPath = "/System/Applications/Utilities/Terminal.app"

    static func launchSSH(toAlias alias: String, terminalAppPath: String) throws {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }

        let scriptURL = try writeTempScript(for: trimmedAlias)
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

    private static func writeTempScript(for alias: String) throws -> URL {
        let escaped = alias.replacingOccurrences(of: "'", with: "'\\''")
        let body = """
        #!/bin/bash
        clear
        exec ssh '\(escaped)'
        """

        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("sshcm-\(UUID().uuidString).command")
        try body.data(using: .utf8)?.write(to: url, options: .atomic)
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
