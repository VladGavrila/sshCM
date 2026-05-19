import Foundation

struct SSHHost: Identifiable, Hashable {
    let id: UUID
    var aliases: [String]
    var searchAliases: [String]
    var hostName: String?
    var user: String?
    var port: Int?
    var identityFile: String?
    var proxyJump: String?
    var rawLines: [String]

    init(
        id: UUID = UUID(),
        aliases: [String],
        searchAliases: [String] = [],
        hostName: String? = nil,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil,
        proxyJump: String? = nil,
        rawLines: [String] = []
    ) {
        self.id = id
        self.aliases = aliases
        self.searchAliases = searchAliases
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.rawLines = rawLines
    }

    var title: String {
        aliases.joined(separator: " ")
    }
}
