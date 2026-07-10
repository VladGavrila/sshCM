import Foundation

/// Central registry of every UserDefaults / @AppStorage key used in the app.
/// Using typed enum cases instead of scattered string literals prevents typos
/// from silently creating separate, always-empty keys and losing persisted data.
enum AppStorageKey: String, CaseIterable {
    // MARK: - Favorites (legacy)
    /// Legacy. Per-host favorite flags now live in `~/.ssh/config` as
    /// `# sshCM-favorite:` markers. Read only for the one-time migration in
    /// `TagFavoriteMigration`, then removed.
    case favoriteAliases

    // MARK: - TagsStore
    /// Legacy. Per-host color tags now live in `~/.ssh/config` as `# sshCM-tag:`
    /// markers. Read only for the one-time migration in `TagFavoriteMigration`,
    /// then removed. (`hostTagOrder` / `hostTagNames` are global catalog state
    /// and remain owned by `TagsStore`.)
    case hostTags
    case hostTagOrder
    case hostTagNames
    /// Set once `favoriteAliases` / `hostTags` have been migrated into the config
    /// file, so the migration never re-runs.
    case migratedTagsFavoritesToConfig

    // MARK: - HostKeyBypassStore
    case hostKeyBypassAliases

    // MARK: - HostsFilePublisher
    case publishAliasesToHostsFile

    // MARK: - UpdateChecker
    case autoCheckForUpdates
    case updateLastCheck
    case skippedUpdateVersion

    // MARK: - TerminalLauncher
    case keepTerminalOpenAfterSession

    // MARK: - App presentation (AppPresentation)
    case appPresentation

    // MARK: - ContentView / SettingsView / SeedKeySheet
    case defaultTerminalAppPath
    case hostsViewMode
    case showOnlyReachable
    case defaultPublicKeyPath

    // MARK: - VNCLauncher
    case defaultMacOSVNCAppPath
    /// Legacy. Read only for one-time migration into `RemoteAppsStore`.
    case defaultLinuxVNCAppPath

    // MARK: - RemoteAppsStore
    case remoteAccessApps

    // MARK: - ZonesStore
    case zones
    case selectedZone
}
