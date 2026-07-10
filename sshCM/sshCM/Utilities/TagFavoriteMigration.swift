import Foundation

/// One-time migration that lifts per-host color tags and favorite flags out of
/// `UserDefaults` (where earlier versions kept them, keyed by primary alias) and
/// writes them onto the hosts in `~/.ssh/config` as `# sshCM-tag:` /
/// `# sshCM-favorite:` markers.
///
/// This is the impure counterpart to `SSHConfigFile.applyMigratedTagsFavorites`:
/// it reads the legacy defaults, drives one batched config write through
/// `ConfigStore.updateAll`, then clears the old keys and records a flag so it
/// never runs again. Unlike `migrateLegacyOSMarkers` (which re-reads a marker
/// still present in the file on every load), the source here is `UserDefaults`,
/// which we clear — so the migration must persist eagerly and guard on a flag.
///
/// The global tag catalog (`hostTagOrder` / `hostTagNames`) is deliberately left
/// alone — it stays owned by `TagsStore`.
@MainActor
enum TagFavoriteMigration {
    static func runIfNeeded(store: ConfigStore, defaults: UserDefaults = .standard) {
        let flagKey = AppStorageKey.migratedTagsFavoritesToConfig.rawValue
        guard !defaults.bool(forKey: flagKey) else { return }

        let favorites = Set(defaults.stringArray(forKey: AppStorageKey.favoriteAliases.rawValue) ?? [])
        var tags: [String: HostTag] = [:]
        if let raw = defaults.dictionary(forKey: AppStorageKey.hostTags.rawValue) as? [String: String] {
            for (alias, value) in raw {
                if let tag = HostTag(rawValue: value) { tags[alias] = tag }
            }
        }

        if !favorites.isEmpty || !tags.isEmpty {
            // `publish: false` — tags/favorites never affect the `/etc/hosts`
            // managed block, so there's nothing to re-sync (and no admin prompt).
            store.updateAll(publish: false) { host in
                guard let alias = host.aliases.first, !alias.isEmpty else { return }
                if favorites.contains(alias) { host.isFavorite = true }
                if let tag = tags[alias] { host.tag = tag }
            }
        }

        defaults.removeObject(forKey: AppStorageKey.favoriteAliases.rawValue)
        defaults.removeObject(forKey: AppStorageKey.hostTags.rawValue)
        defaults.set(true, forKey: flagKey)
    }
}
