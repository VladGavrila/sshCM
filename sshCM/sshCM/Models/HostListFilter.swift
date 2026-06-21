import Foundation

/// Pure, testable filtering and sorting logic extracted from ContentView.sortedHosts.
/// All store queries are injected as closures so this type has no dependency on
/// SwiftUI, AppKit, or the concrete store types.
struct HostListFilter {
    var searchText: String
    var showOnlyReachable: Bool

    init(searchText: String = "", showOnlyReachable: Bool = false) {
        self.searchText = searchText
        self.showOnlyReachable = showOnlyReachable
    }

    /// Returns `hosts` sorted and filtered according to the current filter state.
    ///
    /// - Parameters:
    ///   - hosts: Flat list from ConfigStore.
    ///   - isFavorite: Returns `true` when a primary alias is a user favourite.
    ///   - tagRank: Returns the sort rank for a primary alias (lower = earlier).
    ///             The caller is responsible for returning an appropriate "untagged"
    ///             fallback (typically `HostTag.allCases.count`).
    ///   - tagName: Returns the display name of the alias's color tag, or `nil`
    ///              when no tag is set (used as a search haystack field).
    ///   - isReachable: Returns `true` when the host is known to be reachable.
    func apply(
        hosts: [SSHHost],
        isFavorite: (String) -> Bool,
        tagRank: (String) -> Int,
        tagName: (String) -> String?,
        isReachable: (SSHHost) -> Bool
    ) -> [SSHHost] {
        let sorted = hosts.sorted { a, b in
            let aAlias = a.aliases.first ?? ""
            let bAlias = b.aliases.first ?? ""

            let aFav = isFavorite(aAlias)
            let bFav = isFavorite(bAlias)
            if aFav != bFav { return aFav }

            let aTagRank = tagRank(aAlias)
            let bTagRank = tagRank(bAlias)
            if aTagRank != bTagRank { return aTagRank < bTagRank }

            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        let reachFiltered = showOnlyReachable ? sorted.filter(isReachable) : sorted

        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return reachFiltered }

        return reachFiltered.filter { host in
            let alias = host.aliases.first ?? ""
            var haystacks: [String?] = [
                host.title,
                host.hostName,
                host.user,
                host.identityFile,
                host.proxyJump,
                host.port.map(String.init),
                alias.isEmpty ? nil : tagName(alias)
            ]
            haystacks.append(contentsOf: host.searchAliases.map { Optional($0) })
            return haystacks.contains { value in
                guard let value, !value.isEmpty else { return false }
                return value.localizedCaseInsensitiveContains(query)
            }
        }
    }
}
