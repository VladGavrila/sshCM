import Foundation
import Observation

/// Tracks hosts (by primary alias) for which the user has opted to permanently
/// bypass strict host-key checking. Stored in UserDefaults. This deliberately
/// weakens security for the chosen hosts, so it is only ever set through the
/// explicit remediation dialog.
@MainActor
@Observable
final class HostKeyBypassStore {
    private(set) var aliases: Set<String>

    private let defaultsKey = AppStorageKey.hostKeyBypassAliases.rawValue
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: defaultsKey) ?? []
        self.aliases = Set(stored)
    }

    func isBypassed(_ alias: String) -> Bool {
        guard !alias.isEmpty else { return false }
        return aliases.contains(alias)
    }

    func setBypassed(_ bypassed: Bool, for alias: String) {
        guard !alias.isEmpty else { return }
        if bypassed {
            aliases.insert(alias)
        } else {
            aliases.remove(alias)
        }
        persist()
    }

    private func persist() {
        defaults.set(Array(aliases), forKey: defaultsKey)
    }
}
