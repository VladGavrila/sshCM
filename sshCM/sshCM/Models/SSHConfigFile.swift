import Foundation

enum SSHConfigBlock {
    case host(SSHHost)
    case raw(String)
}

struct SSHConfigFile {
    var blocks: [SSHConfigBlock]

    init(blocks: [SSHConfigBlock] = []) {
        self.blocks = blocks
    }

    var hosts: [SSHHost] {
        blocks.compactMap { if case .host(let h) = $0 { return h } else { return nil } }
    }

    mutating func append(host: SSHHost) {
        if !endsWithBlankLine {
            blocks.append(.raw(""))
        }
        blocks.append(.host(host))
    }

    mutating func remove(id: UUID) {
        guard let idx = blocks.firstIndex(where: {
            if case .host(let h) = $0 { return h.id == id } else { return false }
        }) else { return }
        blocks.remove(at: idx)
        if idx < blocks.count, case .raw(let s) = blocks[idx], s.isEmpty {
            blocks.remove(at: idx)
        }
    }

    mutating func update(_ host: SSHHost) {
        guard let idx = blocks.firstIndex(where: {
            if case .host(let h) = $0 { return h.id == host.id } else { return false }
        }) else { return }
        blocks[idx] = .host(host)
    }

    /// Reuses the ids of hosts from a previous version of this file, matched by
    /// primary alias, so host identity survives a reparse. Without this, every
    /// reload assigns fresh UUIDs and orphans any host reference captured before
    /// the reload (e.g. a host being edited from the command palette).
    mutating func preserveIDs(from old: SSHConfigFile) {
        var idsByAlias: [String: [UUID]] = [:]
        for host in old.hosts {
            guard let alias = host.aliases.first else { continue }
            idsByAlias[alias, default: []].append(host.id)
        }
        blocks = blocks.map { block in
            guard case .host(var h) = block,
                  let alias = h.aliases.first,
                  var queue = idsByAlias[alias], !queue.isEmpty
            else { return block }
            h.id = queue.removeFirst()
            idsByAlias[alias] = queue
            return .host(h)
        }
    }

    /// One-time migration from the old fixed macOS/Linux `os` classification to
    /// the new named `remoteApp` list. Runs on every load but only ever touches
    /// hosts that still carry a legacy `os` marker and no `remoteApp` yet, so it's
    /// a no-op once a host has been resaved. `linuxAppPathConfigured` tells us
    /// whether the user had a Linux VNC app path set, which `RemoteAppsStore`
    /// seeds as an entry named `RemoteAccessApp.legacyLinuxAppName` — without that
    /// path there's no app for a `.linux` host to resolve to, so it's left unset
    /// rather than pointing at a name nothing backs.
    mutating func migrateLegacyOSMarkers(linuxAppPathConfigured: Bool) {
        blocks = blocks.map { block in
            guard case .host(var h) = block, h.remoteApp == nil, let os = h.os else { return block }
            switch os {
            case .macOS:
                h.remoteApp = RemoteAccessApp.screenSharingName
            case .linux:
                if linuxAppPathConfigured {
                    h.remoteApp = RemoteAccessApp.legacyLinuxAppName
                }
            }
            h.os = nil
            return .host(h)
        }
    }

    /// One-time migration of per-host color tags and favorite flags out of
    /// `UserDefaults` (keyed by primary alias) and onto the hosts themselves,
    /// where they now live as `# sshCM-tag:` / `# sshCM-favorite:` markers. The
    /// impure parts — reading the old defaults, clearing them, and setting the
    /// migration flag — belong to `TagFavoriteMigration`; this stays a pure,
    /// testable transform. Returns `true` if any host changed.
    @discardableResult
    mutating func applyMigratedTagsFavorites(favorites: Set<String>, tags: [String: HostTag]) -> Bool {
        var changed = false
        blocks = blocks.map { block in
            guard case .host(var h) = block, let alias = h.aliases.first, !alias.isEmpty else { return block }
            var didChange = false
            if favorites.contains(alias), !h.isFavorite {
                h.isFavorite = true
                didChange = true
            }
            if let tag = tags[alias], h.tag != tag {
                h.tag = tag
                didChange = true
            }
            guard didChange else { return block }
            changed = true
            return .host(h)
        }
        return changed
    }

    private var endsWithBlankLine: Bool {
        guard let last = blocks.last else { return true }
        if case .raw(let s) = last, s.isEmpty { return true }
        return false
    }

    func serialize() -> String {
        var out: [String] = []
        for block in blocks {
            switch block {
            case .raw(let s):
                out.append(s)
            case .host(let h):
                out.append(contentsOf: serializeHost(h))
            }
        }
        var joined = out.joined(separator: "\n")
        if !joined.hasSuffix("\n") { joined.append("\n") }
        return joined
    }

    private func serializeHost(_ h: SSHHost) -> [String] {
        var lines: [String] = []
        lines.append("Host \(h.aliases.joined(separator: " "))")
        if !h.searchAliases.isEmpty {
            lines.append("    \(SSHConfigParser.searchAliasesMarker) \(h.searchAliases.joined(separator: ", "))")
        }
        if !h.alternateUsers.isEmpty {
            lines.append("    \(SSHConfigParser.alternateUsersMarker) \(h.alternateUsers.joined(separator: ", "))")
        }
        for f in h.localForwards {
            let suffix = f.note.isEmpty ? "" : " \(f.note)"
            lines.append("    \(SSHConfigParser.localForwardMarker) \(f.spec)\(suffix)")
        }
        for f in h.remoteForwards {
            let suffix = f.note.isEmpty ? "" : " \(f.note)"
            lines.append("    \(SSHConfigParser.remoteForwardMarker) \(f.spec)\(suffix)")
        }
        if let remoteApp = h.remoteApp, !remoteApp.isEmpty {
            lines.append("    \(SSHConfigParser.remoteAppMarker) \(remoteApp)")
        }
        if let port = h.vncPort, port != 5900 {
            lines.append("    \(SSHConfigParser.vncPortMarker) \(port)")
        }
        if h.allowsSMB {
            lines.append("    \(SSHConfigParser.smbMarker) yes")
        }
        if let zone = h.zone, !zone.isEmpty {
            lines.append("    \(SSHConfigParser.zoneMarker) \(zone)")
        }
        if let tag = h.tag {
            lines.append("    \(SSHConfigParser.tagMarker) \(tag.rawValue)")
        }
        if h.isFavorite {
            lines.append("    \(SSHConfigParser.favoriteMarker) yes")
        }
        if let v = h.hostName, !v.isEmpty { lines.append(indented("HostName", v)) }
        if let v = h.user, !v.isEmpty { lines.append(indented("User", v)) }
        if let p = h.port { lines.append(indented("Port", String(p))) }
        if let v = h.identityFile, !v.isEmpty { lines.append(indented("IdentityFile", v)) }
        if let v = h.proxyJump, !v.isEmpty { lines.append(indented("ProxyJump", v)) }
        lines.append(contentsOf: h.rawLines)
        return lines
    }

    private func indented(_ key: String, _ value: String) -> String {
        let needsQuotes = value.contains(" ") || value.contains("\t")
        let v = needsQuotes ? "\"\(value)\"" : value
        return "    \(key) \(v)"
    }
}
