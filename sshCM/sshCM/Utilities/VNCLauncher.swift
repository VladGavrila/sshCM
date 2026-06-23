import AppKit
import Foundation

enum VNCLauncher {
    static let defaultMacOSVNCAppPath = "/System/Applications/Screen Sharing.app"

    static func launch(
        toHost hostName: String,
        port: Int,
        remoteApp: RemoteAccessApp?,
        user: String? = nil
    ) throws {
        let trimmedHost = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw VNCLaunchError.invalidHost
        }
        let trimmedUser = user?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let remoteApp, !remoteApp.appPath.isEmpty, FileManager.default.fileExists(atPath: remoteApp.appPath) else {
            // No configured/available app — fall back to the system's registered
            // vnc:// handler rather than failing.
            guard let url = vncURL(host: trimmedHost, port: port, user: trimmedUser) else {
                throw VNCLaunchError.invalidHost
            }
            NSWorkspace.shared.open(url)
            return
        }

        let appURL = URL(fileURLWithPath: remoteApp.appPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if remoteApp.name == RemoteAccessApp.screenSharingName {
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
        } else if remoteApp.showsPort {
            // Third-party VNC viewers (e.g. TigerVNC) generally don't register as a
            // vnc:// URL handler, so passing a URL silently fails to populate the host
            // and lets macOS fall back to the system's default handler instead. Launch
            // the app directly with "host:port" as a command-line argument instead.
            configuration.arguments = ["\(trimmedHost):\(port)"]
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    NSLog("VNCLauncher failed: \(error.localizedDescription)")
                }
            }
        } else if let url = customSchemeURL(forAppAt: remoteApp.appPath, host: trimmedHost) {
            // TeamViewer and RustDesk don't pick up the host from a bare CLI argument
            // (launching the app that way opens it with nothing pre-filled) — they need
            // their own URL scheme invoked instead, with the host embedded in it.
            // Identified by bundle ID rather than `remoteApp.name` since the user can
            // rename the configured entry to anything.
            NSWorkspace.shared.open(url)
        } else {
            // Apps that connect by their own identifier rather than a port get just the
            // bare IP/hostname as an argument.
            configuration.arguments = [trimmedHost]
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    NSLog("VNCLauncher failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Bundle IDs of apps that connect via a custom URL scheme (with the host embedded)
    /// rather than via a CLI argument, and the URL template to use for each.
    private static func customSchemeURL(forAppAt appPath: String, host: String) -> URL? {
        guard let bundleID = Bundle(path: appPath)?.bundleIdentifier,
              let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        switch bundleID {
        case "com.teamviewer.TeamViewer":
            return URL(string: "teamviewer10://control?device=\(encodedHost)")
        case "com.carriez.rustdesk":
            return URL(string: "rustdesk://\(encodedHost)")
        default:
            return nil
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
