import Foundation

/// Pure, testable filtering and sorting logic extracted from ContentView.sortedHosts.
/// All store queries are injected as closures so this type has no dependency on
/// SwiftUI, AppKit, or the concrete store types.
struct HostListFilter {
    var searchText: String
    var showOnlyReachable: Bool
    var zone: String?

    init(searchText: String = "", showOnlyReachable: Bool = false, zone: String? = nil) {
        self.searchText = searchText
        self.showOnlyReachable = showOnlyReachable
        self.zone = zone
    }

    /// Returns `hosts` sorted and filtered according to the current filter state.
    ///
    /// - Parameters:
    ///   - hosts: Flat list from ConfigStore.
    ///   - tagRank: Maps a host's `tag` to its sort rank (lower = earlier). The
    ///             caller supplies an "untagged" fallback (typically
    ///             `HostTag.allCases.count`) for the `nil` case.
    ///   - tagName: Maps a host's `tag` to its display name, or `nil` when no tag
    ///              is set (used as a search haystack field).
    ///   - isReachable: Returns `true` when the host is known to be reachable.
    ///
    /// Favorite ordering reads `SSHHost.isFavorite` directly. `zone` (nil = All
    /// Zones) filters to hosts in that exact zone before reachability/text
    /// filtering apply; it never affects sort order.
    func apply(
        hosts: [SSHHost],
        tagRank: (HostTag?) -> Int,
        tagName: (HostTag?) -> String?,
        isReachable: (SSHHost) -> Bool
    ) -> [SSHHost] {
        let sorted = hosts.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }

            let aTagRank = tagRank(a.tag)
            let bTagRank = tagRank(b.tag)
            if aTagRank != bTagRank { return aTagRank < bTagRank }

            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        let zoneFiltered = zone.map { z in sorted.filter { $0.zone == z } } ?? sorted

        let reachFiltered = showOnlyReachable ? zoneFiltered.filter(isReachable) : zoneFiltered

        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return reachFiltered }

        return reachFiltered.filter { host in
            var haystacks: [String?] = [
                host.title,
                host.hostName,
                host.user,
                host.identityFile,
                host.proxyJump,
                host.port.map(String.init),
                tagName(host.tag),
                host.zone
            ]
            haystacks.append(contentsOf: host.searchAliases.map { Optional($0) })
            return haystacks.contains { value in
                guard let value, !value.isEmpty else { return false }
                return value.localizedCaseInsensitiveContains(query)
            }
        }
    }
}
