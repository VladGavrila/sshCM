import AppKit
import Foundation

enum VNCLauncher {
    static let defaultMacOSVNCAppPath = "/System/Applications/Screen Sharing.app"

    static func launch(
        toHost hostName: String,
        port: Int,
        os: SSHHost.OS?,
        user: String? = nil,
        macOSAppPath: String,
        linuxAppPath: String
    ) throws {
        let trimmedHost = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw VNCLaunchError.invalidHost
        }
        let trimmedUser = user?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedAppPath: String
        switch os {
        case .macOS:
            resolvedAppPath = macOSAppPath.isEmpty ? defaultMacOSVNCAppPath : macOSAppPath
        case .linux:
            resolvedAppPath = linuxAppPath
        case nil:
            resolvedAppPath = ""
        }

        guard !resolvedAppPath.isEmpty, FileManager.default.fileExists(atPath: resolvedAppPath) else {
            // No configured/available app for this classification — fall back to
            // the system's registered vnc:// handler rather than failing.
            guard let url = vncURL(host: trimmedHost, port: port, user: trimmedUser) else {
                throw VNCLaunchError.invalidHost
            }
            NSWorkspace.shared.open(url)
            return
        }

        let appURL = URL(fileURLWithPath: resolvedAppPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if os == .macOS {
            // Screen Sharing.app is Apple's own client and natively understands vnc://
            // URLs, including a "user@host" form that pre-fills the login name.
            guard let url = vncURL(host: trimmedHost, port: port, user: trimmedUser) else {
                throw VNCLaunchError.invalidHost
            }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    NSLog("VNCLauncher failed: \(error.localizedDescription)")
                }
            }
        } else {
            // Third-party viewers (e.g. TigerVNC) generally don't register as a vnc://
            // URL handler, so passing a URL silently fails to populate the host and
            // lets macOS fall back to the system's default handler instead. Launch the
            // app directly with "host:port" as a command-line argument instead.
            configuration.arguments = ["\(trimmedHost):\(port)"]
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    NSLog("VNCLauncher failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func vncURL(host: String, port: Int, user: String?) -> URL? {
        guard let user, !user.isEmpty,
              let encodedUser = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) else {
            return URL(string: "vnc://\(host):\(port)")
        }
        return URL(string: "vnc://\(encodedUser)@\(host):\(port)")
    }
}

enum VNCLaunchError: LocalizedError {
    case invalidHost

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Host has no HostName to connect to via VNC."
        }
    }
}
