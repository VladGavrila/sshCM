import Foundation

/// Stateless helpers to turn hosts (plus their tag/favorite metadata) into a
/// portable JSON document and back. UI lives in `ExportHostsSheet` /
/// `ImportHostsSheet`; this namespace only does the model<->bytes conversion.
enum HostPortability {
    /// Builds an export document for `hosts`. The color tag and favorite flag
    /// travel on the host itself (`SSHHost.tag` / `.isFavorite`).
    static func makeDocument(hosts: [SSHHost]) -> HostExportDocument {
        let exported = hosts.map { ExportedHost(host: $0) }
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
