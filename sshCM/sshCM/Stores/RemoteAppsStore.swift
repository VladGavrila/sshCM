import Foundation
import Observation

/// User-managed list of remote-access apps (TeamViewer, RustDesk, TigerVNC, …)
/// offered alongside the always-available, built-in Screen Sharing entry.
/// Screen Sharing itself is never stored here — see `selectableApps`.
@MainActor
@Observable
final class RemoteAppsStore {
    private(set) var apps: [RemoteAccessApp] = []

    init() {
        apps = Self.loadApps()
        migrateLegacyLinuxAppIfNeeded()
    }

    func add(name: String, appPath: String, showsPort: Bool) {
        apps.append(RemoteAccessApp(name: name, appPath: appPath, showsPort: showsPort))
        save()
    }

    func update(_ app: RemoteAccessApp) {
        guard let idx = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[idx] = app
        save()
    }

    func remove(id: UUID) {
        apps.removeAll { $0.id == id }
        save()
    }

    /// Drops any in-progress entries that never had an app chosen — e.g. one
    /// created by "Add Remote App" and then abandoned. Called when the Settings
    /// Apps tab is left, so a half-filled-in row doesn't linger or get persisted.
    func pruneIncomplete() {
        apps.removeAll { $0.appPath.isEmpty }
        save()
    }

    /// Every app a host can pick, with the built-in Screen Sharing entry first.
    /// Entries with no app chosen yet are excluded — they're not a usable choice.
    func selectableApps(screenSharingPath: String) -> [RemoteAccessApp] {
        [RemoteAccessApp(name: RemoteAccessApp.screenSharingName, appPath: screenSharingPath, showsPort: true)]
            + apps.filter { !$0.appPath.isEmpty }
    }

    /// Resolves a host's stored `remoteApp` name to the app that currently
    /// backs it, usable from contexts without a `RemoteAppsStore` instance
    /// (e.g. the command-palette closures configured in `sshCMApp`, which only
    /// have `UserDefaults` to read from). Returns `nil` if unset or if the
    /// name no longer matches any configured app (e.g. it was removed).
    static func resolve(name: String?, screenSharingPath: String) -> RemoteAccessApp? {
        guard let name else { return nil }
        if name == RemoteAccessApp.screenSharingName {
            return RemoteAccessApp(name: name, appPath: screenSharingPath, showsPort: true)
        }
        return loadApps().first { $0.name == name }
    }

    private static func loadApps() -> [RemoteAccessApp] {
        guard let data = UserDefaults.standard.data(forKey: AppStorageKey.remoteAccessApps.rawValue),
              let decoded = try? JSONDecoder().decode([RemoteAccessApp].self, from: data) else { return [] }
        return decoded
    }

    /// Seeds a "Linux VNC App" entry from the old fixed Linux VNC app path
    /// setting, once, so hosts migrated by `SSHConfigFile.migrateLegacyOSMarkers`
    /// (which points them at `RemoteAccessApp.legacyLinuxAppName`) resolve to
    /// something. Runs at most once per install, gated by its own flag rather
    /// than "is the list empty" so a user who deletes the migrated entry later
    /// doesn't get it silently recreated.
    private func migrateLegacyLinuxAppIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didMigrateKey) else { return }
        defaults.set(true, forKey: Self.didMigrateKey)
        let legacyPath = defaults.string(forKey: AppStorageKey.defaultLinuxVNCAppPath.rawValue) ?? ""
        guard !legacyPath.isEmpty, !apps.contains(where: { $0.name == RemoteAccessApp.legacyLinuxAppName }) else { return }
        apps.append(RemoteAccessApp(name: RemoteAccessApp.legacyLinuxAppName, appPath: legacyPath, showsPort: true))
        save()
    }

    private static let didMigrateKey = "remoteAccessAppsDidMigrateLegacyLinux"

    /// Persists only entries with an app chosen — an in-progress blank row
    /// (added but abandoned before `pruneIncomplete()` runs, e.g. the app was
    /// quit without closing Settings) is never written to disk.
    private func save() {
        guard let data = try? JSONEncoder().encode(apps.filter { !$0.appPath.isEmpty }) else { return }
        UserDefaults.standard.set(data, forKey: AppStorageKey.remoteAccessApps.rawValue)
    }
}
