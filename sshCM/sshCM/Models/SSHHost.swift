import Foundation

struct SSHHost: Identifiable, Hashable {
    enum OS: String, CaseIterable, Hashable {
        case macOS, linux
    }

    var id: UUID
    var aliases: [String]
    var searchAliases: [String]
    var hostName: String?
    var user: String?
    var port: Int?
    var identityFile: String?
    var proxyJump: String?
    var alternateUsers: [String]
    /// Legacy best-effort/manual OS classification. Only read from old config
    /// files for one-time migration into `remoteApp` — see
    /// `SSHConfigFile.migrateLegacyOSMarkers`; never written back out.
    var os: OS?
    /// Name of the selected entry from the user's remote-app list (or
    /// `RemoteAccessApp.screenSharingName`), used to pick a viewer for the
    /// "Connect via VNC"/remote-access action. `nil` means unset.
    var remoteApp: String?
    /// VNC port override. `nil` means the default (5900). Only meaningful
    /// when the selected `remoteApp` has `showsPort == true`.
    var vncPort: Int?
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
        os: OS? = nil,
        remoteApp: String? = nil,
        vncPort: Int? = nil,
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
        self.os = os
        self.remoteApp = remoteApp
        self.vncPort = vncPort
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
