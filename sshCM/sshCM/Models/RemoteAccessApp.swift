import Foundation

/// One entry in the user-configurable "Remote app" list offered per host (the
/// generalized successor to the old fixed macOS/Linux VNC app split). Screen
/// Sharing is always available and is represented as a synthesized instance
/// with `name == screenSharingName` rather than being stored in the list —
/// see `RemoteAppsStore`.
struct RemoteAccessApp: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var appPath: String
    /// Whether the VNC port field/concept applies to this app (TigerVNC,
    /// RealVNC, …). Apps that connect by their own identifier rather than a
    /// host:port pair (TeamViewer, RustDesk, …) leave this off so the port
    /// field is hidden wherever the app is selected.
    var showsPort: Bool

    init(id: UUID = UUID(), name: String, appPath: String, showsPort: Bool) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.showsPort = showsPort
    }

    static let screenSharingName = "Screen Sharing"
    /// Name seeded once for users migrating from the old fixed "Linux VNC app"
    /// setting — see `SSHConfigFile.migrateLegacyOSMarkers`.
    static let legacyLinuxAppName = "Linux VNC App"
}
