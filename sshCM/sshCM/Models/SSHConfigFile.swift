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
