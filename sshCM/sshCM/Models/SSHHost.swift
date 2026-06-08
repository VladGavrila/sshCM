import Foundation

struct SSHHost: Identifiable, Hashable {
    var id: UUID
    var aliases: [String]
    var searchAliases: [String]
    var hostName: String?
    var user: String?
    var port: Int?
    var identityFile: String?
    var proxyJump: String?
    var alternateUsers: [String]
    /// On-demand `-L` forwards (display label + spec). Stored as sshCM metadata
    /// comments, not native `LocalForward` directives, so plain connects don't
    /// forward — see `PortForward`.
    var localForwards: [PortForward]
    /// On-demand `-R` (reverse) forwards.
    var remoteForwards: [PortForward]
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
        alternateUsers: [String] = [],
        localForwards: [PortForward] = [],
        remoteForwards: [PortForward] = [],
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
        self.alternateUsers = alternateUsers
        self.localForwards = localForwards
        self.remoteForwards = remoteForwards
        self.rawLines = rawLines
    }

    var hasForwards: Bool {
        !localForwards.isEmpty || !remoteForwards.isEmpty
    }

    var title: String {
        aliases.joined(separator: " ")
    }

    static func jumpHostAliases(in hosts: [SSHHost]) -> Set<String> {
        var aliases = Set<String>()
        for host in hosts {
            guard let pj = host.proxyJump?.trimmingCharacters(in: .whitespaces), !pj.isEmpty else { continue }
            for hop in pj.split(separator: ",", omittingEmptySubsequences: true) {
                let trimmed = hop.trimmingCharacters(in: .whitespaces)
                let afterAt: String
                if let atIdx = trimmed.lastIndex(of: "@") {
                    afterAt = String(trimmed[trimmed.index(after: atIdx)...])
                } else {
                    afterAt = trimmed
                }
                let aliasPart = afterAt.split(separator: ":", maxSplits: 1).first.map(String.init) ?? afterAt
                if !aliasPart.isEmpty {
                    aliases.insert(aliasPart)
                }
            }
        }
        return aliases
    }
}
