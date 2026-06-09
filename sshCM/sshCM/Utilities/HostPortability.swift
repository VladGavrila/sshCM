import Foundation

/// Stateless helpers to turn hosts (plus their tag/favorite metadata) into a
/// portable JSON document and back. UI lives in `ExportHostsSheet` /
/// `ImportHostsSheet`; this namespace only does the model<->bytes conversion.
enum HostPortability {
    /// Builds an export document for `hosts`, pulling each host's color tag and
    /// favorite flag from the stores (keyed by primary alias, matching how the
    /// rest of the app keys per-host metadata).
    @MainActor
    static func makeDocument(
        hosts: [SSHHost],
        tagsStore: TagsStore,
        favorites: FavoritesStore
    ) -> HostExportDocument {
        let exported = hosts.map { host -> ExportedHost in
            let alias = host.aliases.first
            let tag = alias.flatMap { tagsStore.tag(for: $0) }
            let favorite = alias.map { favorites.isFavorite($0) } ?? false
            return ExportedHost(host: host, tag: tag, favorite: favorite)
        }
        return HostExportDocument(exportedAt: Date(), hosts: exported)
    }

    static func encode(_ document: HostExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> HostExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HostExportDocument.self, from: data)
    }
}
