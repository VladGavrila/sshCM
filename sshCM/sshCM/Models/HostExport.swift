import Foundation

/// Portable, versioned representation of a set of hosts for export/import.
///
/// This is intentionally decoupled from `SSHConfigFile`: it carries only the
/// hosts the user selected (never global directives or `Match` blocks) plus the
/// app's UI metadata (color tag, favorite) that lives outside `~/.ssh/config`.
/// Host `UUID`s are deliberately omitted — they're machine-local; imports mint
/// fresh ones and match conflicts by primary alias, mirroring
/// `SSHConfigFile.preserveIDs(from:)`.
struct HostExportDocument: Codable {
    var formatVersion: Int = 1
    var exportedAt: Date
    var hosts: [ExportedHost]
}

/// One host in an export document. `id` is a transient identity used only for
/// SwiftUI list selection; it is never written to or read from the JSON file.
struct ExportedHost: Codable, Identifiable {
    var id = UUID()
    var aliases: [String]
    var searchAliases: [String]
    var hostName: String?
    var user: String?
    var port: Int?
    var identityFile: String?
    var proxyJump: String?
    var alternateUsers: [String]
    var localForwards: [PortForward]
    var remoteForwards: [PortForward]
    var rawLines: [String]
    var tag: HostTag?
    var favorite: Bool
    var zone: String?

    /// Excludes `id` so it is neither encoded nor required when decoding (it
    /// falls back to the `var id = UUID()` default on import).
    private enum CodingKeys: String, CodingKey {
        case aliases, searchAliases, hostName, user, port, identityFile
        case proxyJump, alternateUsers, localForwards, remoteForwards, rawLines
        case tag, favorite, zone
    }

    /// The key under which tags/favorites/etc. are stored for this host.
    var primaryAlias: String? { aliases.first }

    init(
        aliases: [String],
        searchAliases: [String],
        hostName: String?,
        user: String?,
        port: Int?,
        identityFile: String?,
        proxyJump: String?,
        alternateUsers: [String],
        localForwards: [PortForward],
        remoteForwards: [PortForward],
        rawLines: [String],
        tag: HostTag?,
        favorite: Bool,
        zone: String? = nil
    ) {
        self.aliases = aliases
        self.searchAliases = searchAliases
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.alternateUsers = alternateUsers
        self.localForwards = localForwards
        self.remoteForwards = remoteForwards
        self.rawLines = rawLines
        self.tag = tag
        self.favorite = favorite
        self.zone = zone
    }

    init(host: SSHHost) {
        self.init(
            aliases: host.aliases,
            searchAliases: host.searchAliases,
            hostName: host.hostName,
            user: host.user,
            port: host.port,
            identityFile: host.identityFile,
            proxyJump: host.proxyJump,
            alternateUsers: host.alternateUsers,
            localForwards: host.localForwards,
            remoteForwards: host.remoteForwards,
            rawLines: host.rawLines,
            tag: host.tag,
            favorite: host.isFavorite,
            zone: host.zone
        )
    }

    /// Rebuilds an `SSHHost`. Pass an existing `id` to overwrite a host in place
    /// (the conflict "use imported" path); omit it to create a brand-new host.
    func toSSHHost(id: UUID = UUID()) -> SSHHost {
        SSHHost(
            id: id,
            aliases: aliases,
            searchAliases: searchAliases,
            hostName: hostName,
            user: user,
            port: port,
            identityFile: identityFile,
            proxyJump: proxyJump,
            alternateUsers: alternateUsers,
            localForwards: localForwards,
            remoteForwards: remoteForwards,
            zone: zone,
            tag: tag,
            isFavorite: favorite,
            rawLines: rawLines
        )
    }
}
