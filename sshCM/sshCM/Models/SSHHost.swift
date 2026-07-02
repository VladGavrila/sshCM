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
    /// Whether this host exposes SMB file sharing. When `true`, a "Connect via
    /// SMB" action (and grid/list icon + palette entry) is offered, opening the
    /// host's `HostName` as an `smb://` URL in Finder.
    var allowsSMB: Bool
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
        allowsSMB: Bool = false,
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
        self.allowsSMB = allowsSMB
        self.rawLines = rawLines
    }

    var hasForwards: Bool {
        !localForwards.isEmpty || !remoteForwards.isEmpty
    }

    var title: String {
        aliases.joined(separator: " ")
    }

    // MARK: - Import safety

    /// SSH directives an imported host could use to run arbitrary commands the
    /// moment ssh connects. They are dropped from an imported host's `rawLines`
    /// (see `sanitizedForImport`), so a shared/exported hosts file can't smuggle
    /// code execution into `~/.ssh/config` for a directive sshCM doesn't surface
    /// or let the user review.
    static let dangerousImportedDirectives: Set<String> = [
        "proxycommand", "localcommand", "permitlocalcommand"
    ]

    /// Whether a raw config line sets one of `dangerousImportedDirectives`.
    /// Matches both `Key value` and `Key=value`, case-insensitively; comments
    /// and blanks are never dangerous.
    static func isDangerousImportedLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        let keyword = trimmed
            .split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" })
            .first
            .map { $0.lowercased() } ?? ""
        return dangerousImportedDirectives.contains(keyword)
    }

    /// Strips every character not allowed in an SSH alias / `/etc/hosts` hostname
    /// (the same set the add/edit form enforces live), so an imported token can't
    /// carry spaces or commas into the config. Leading `-` is also removed — it's
    /// a legal character mid-token (`web-server`) but a leading one would make ssh
    /// read the token as an option.
    static func sanitizeAliasToken(_ value: String) -> String {
        let filtered = String(String.UnicodeScalarView(
            value.unicodeScalars.filter { HostsFileBlock.hostnameAllowedCharacters.contains($0) }
        ))
        return String(filtered.drop(while: { $0 == "-" }))
    }

    private static func sanitizeAliasTokens(_ values: [String]) -> [String] {
        values.map(sanitizeAliasToken).filter { !$0.isEmpty }
    }

    /// A copy safe to persist to `~/.ssh/config` from an imported document:
    /// alias/user tokens are reduced to permitted characters, and any
    /// command-executing directive smuggled into `rawLines` is removed. Used at
    /// the import boundary — hosts created through the UI are already clean.
    func sanitizedForImport() -> SSHHost {
        var copy = self
        copy.aliases = Self.sanitizeAliasTokens(aliases)
        copy.searchAliases = Self.sanitizeAliasTokens(searchAliases)
        copy.alternateUsers = Self.sanitizeAliasTokens(alternateUsers)
        copy.rawLines = rawLines.filter { !Self.isDangerousImportedLine($0) }
        return copy
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
