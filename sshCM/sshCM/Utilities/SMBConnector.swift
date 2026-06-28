import AppKit
import Foundation

/// Opens a host's SMB file share. Rather than simulating Finder's ⌘K
/// "Connect to Server" dialog, we hand an `smb://<host>` URL to the system —
/// Finder is the registered handler and presents the same mount/connect flow
/// with the host pre-populated. Mirrors how `VNCLauncher` uses `vnc://`.
enum SMBConnector {
    static func connect(toHost hostName: String) throws {
        let trimmedHost = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let encodedHost = trimmedHost.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: "smb://\(encodedHost)") else {
            throw SMBConnectError.invalidHost
        }
        NSWorkspace.shared.open(url)
    }
}

enum SMBConnectError: LocalizedError {
    case invalidHost

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Host has no HostName to connect to via SMB."
        }
    }
}
