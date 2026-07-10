import Foundation

/// Pure, testable scoring logic extracted from CommandPaletteView.score(host:query:).
/// Ranks how well a host matches a search query. Higher is better; 0 = no match.
///
/// Score hierarchy (descending):
///   1000  exact primary alias
///    900  exact search alias
///    500+ primary alias prefix (bonus for shorter excess)
///    400+ search alias prefix  (bonus for shorter excess)
///    100  primary alias contains query
///     80  search alias contains query
///     10  any other field (title, hostName, user, identityFile, proxyJump, port, tagName, zone)
///      0  no match
enum HostSearchScorer {
    /// - Parameters:
    ///   - host: The host to score.
    ///   - query: The raw (non-empty, non-trimmed) user query.
    ///   - tagName: The display name of the host's color tag, or `nil`.
    ///              Callers resolve this from their store before calling.
    static func score(host: SSHHost, query: String, tagName: String? = nil) -> Int {
        let q = query.lowercased()
        let alias = (host.aliases.first ?? "").lowercased()

        if !alias.isEmpty {
            if alias == q { return 1000 }
            if alias.hasPrefix(q) { return 500 + max(0, 20 - (alias.count - q.count)) }
            if alias.contains(q) { return 100 }
        }

        for sa in host.searchAliases.map({ $0.lowercased() }) where !sa.isEmpty {
            if sa == q { return 900 }
            if sa.hasPrefix(q) { return 400 + max(0, 20 - (sa.count - q.count)) }
            if sa.contains(q) { return 80 }
        }

        let others: [String?] = [
            host.title, host.hostName, host.user, host.identityFile, host.proxyJump,
            host.port.map(String.init), tagName, host.zone
        ]
        for value in others.compactMap({ $0?.lowercased() }) where !value.isEmpty {
            if value.contains(q) { return 10 }
        }
        return 0
    }
}
