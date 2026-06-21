import Foundation

/// Central registry of every UserDefaults / @AppStorage key used in the app.
/// Using typed enum cases instead of scattered string literals prevents typos
/// from silently creating separate, always-empty keys and losing persisted data.
enum AppStorageKey: String, CaseIterable {
    // MARK: - FavoritesStore
    case favoriteAliases

    // MARK: - TagsStore
    case hostTags
    case hostTagOrder
    case hostTagNames

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
}
