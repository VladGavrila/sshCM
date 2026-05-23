import Foundation

enum SSHConfigParser {
    static func parse(_ text: String) -> SSHConfigFile {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Drop trailing empty produced by terminal newline so we don't double up on serialize.
        var workLines = lines
        if workLines.last == "" { workLines.removeLast() }

        var blocks: [SSHConfigBlock] = []
        var rawBuffer: [String] = []
        var currentHost: SSHHost?
        var inMatchBlock = false

        func flushRaw() {
            if !rawBuffer.isEmpty {
                blocks.append(.raw(rawBuffer.joined(separator: "\n")))
                rawBuffer.removeAll()
            }
        }
        func flushHost() {
            if let h = currentHost {
                blocks.append(.host(h))
                currentHost = nil
            }
        }

        for line in workLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let (keyword, value) = splitKeyValue(trimmed)

            if let kw = keyword, kw.caseInsensitiveCompare("Host") == .orderedSame, !inMatchBlock || true {
                // New Host block always starts fresh.
                inMatchBlock = false
                flushHost()
                flushRaw()
                let aliases = tokenize(value)
                currentHost = SSHHost(aliases: aliases.isEmpty ? [""] : aliases)
                continue
            }

            if currentHost != nil, let parsed = parseSearchAliasesComment(trimmed) {
                currentHost?.searchAliases = parsed
                continue
            }

            if currentHost != nil, let parsed = parseAlternateUsersComment(trimmed) {
                currentHost?.alternateUsers = parsed
                continue
            }

            if let kw = keyword, kw.caseInsensitiveCompare("Match") == .orderedSame {
                flushHost()
                inMatchBlock = true
                rawBuffer.append(line)
                continue
            }

            if inMatchBlock {
                // A non-Host line inside a Match block stays raw.
                rawBuffer.append(line)
                continue
            }

            if var host = currentHost, let kw = keyword {
                if applyKnownKey(kw, value: value, to: &host) {
                    currentHost = host
                    continue
                } else {
                    host.rawLines.append(line)
                    currentHost = host
                    continue
                }
            }

            // Outside any host: comments, blanks, globals, Include lines.
            rawBuffer.append(line)
        }

        flushHost()
        flushRaw()
        return SSHConfigFile(blocks: blocks)
    }

    private static func splitKeyValue(_ trimmed: String) -> (String?, String) {
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return (nil, "") }
        // Allow `Key=Value` and `Key Value`.
        if let eq = trimmed.firstIndex(of: "=") {
            // Only treat as kv if the segment before = is a single token.
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let val = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !key.contains(" ") && !key.contains("\t") {
                return (String(key), String(val))
            }
        }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.isEmpty { return (nil, "") }
        let key = String(parts[0])
        let val = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return (key, val)
    }

    private static func tokenize(_ value: String) -> [String] {
        value.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    static let searchAliasesMarker = "# sshCM-aliases:"
    static let alternateUsersMarker = "# sshCM-users:"

    private static func parseSearchAliasesComment(_ trimmed: String) -> [String]? {
        guard trimmed.lowercased().hasPrefix(searchAliasesMarker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(searchAliasesMarker.count)
        return payload
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func parseAlternateUsersComment(_ trimmed: String) -> [String]? {
        guard trimmed.lowercased().hasPrefix(alternateUsersMarker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(alternateUsersMarker.count)
        return payload
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func applyKnownKey(_ key: String, value rawValue: String, to host: inout SSHHost) -> Bool {
        let value = unquote(rawValue)
        switch key.lowercased() {
        case "hostname":
            host.hostName = value
        case "user":
            host.user = value
        case "port":
            host.port = Int(value)
            if host.port == nil { return false }
        case "identityfile":
            host.identityFile = value
        case "proxyjump":
            host.proxyJump = value
        default:
            return false
        }
        return true
    }
}
