import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    private(set) var aliases: Set<String>

    private let defaultsKey = AppStorageKey.favoriteAliases.rawValue
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: defaultsKey) ?? []
        self.aliases = Set(stored)
    }

    func isFavorite(_ alias: String) -> Bool {
        guard !alias.isEmpty else { return false }
        return aliases.contains(alias)
    }

    func toggle(_ alias: String) {
        guard !alias.isEmpty else { return }
        if aliases.contains(alias) {
            aliases.remove(alias)
        } else {
            aliases.insert(alias)
        }
        persist()
    }

    private func persist() {
        defaults.set(Array(aliases), forKey: defaultsKey)
    }
}
