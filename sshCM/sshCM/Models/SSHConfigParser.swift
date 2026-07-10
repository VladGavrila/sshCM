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

            if let kw = keyword, kw.caseInsensitiveCompare("Host") == .orderedSame {
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

            if currentHost != nil, let forward = parseForwardComment(trimmed, marker: localForwardMarker) {
                currentHost?.localForwards.append(forward)
                continue
            }

            if currentHost != nil, let forward = parseForwardComment(trimmed, marker: remoteForwardMarker) {
                currentHost?.remoteForwards.append(forward)
                continue
            }

            if currentHost != nil, let os = parseOSComment(trimmed) {
                currentHost?.os = os
                continue
            }

            if currentHost != nil, let name = parseRemoteAppComment(trimmed) {
                currentHost?.remoteApp = name
                continue
            }

            if currentHost != nil, let zone = parseZoneComment(trimmed) {
                currentHost?.zone = zone
                continue
            }

            if currentHost != nil, let tag = parseTagComment(trimmed) {
                currentHost?.tag = tag
                continue
            }

            if currentHost != nil, parseFavoriteComment(trimmed) {
                currentHost?.isFavorite = true
                continue
            }

            if currentHost != nil, let port = parseVNCPortComment(trimmed) {
                currentHost?.vncPort = port
                continue
            }

            if currentHost != nil, parseSMBComment(trimmed) {
                currentHost?.allowsSMB = true
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
        let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true) { $0.isWhitespace }
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
    static let localForwardMarker = "# sshCM-localforward:"
    static let remoteForwardMarker = "# sshCM-remoteforward:"
    /// Legacy marker, kept readable only for one-time migration into `remoteApp`.
    static let osMarker = "# sshCM-os:"
    static let remoteAppMarker = "# sshCM-remoteapp:"
    static let vncPortMarker = "# sshCM-vncport:"
    static let smbMarker = "# sshCM-smb:"
    static let zoneMarker = "# sshCM-zone:"
    static let tagMarker = "# sshCM-tag:"
    static let favoriteMarker = "# sshCM-favorite:"

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

    /// Parses one forward marker line (`# sshCM-localforward: <spec> <note>`).
    /// The spec is always a single whitespace-free token; everything after the
    /// first whitespace is the free-text note (which may contain spaces/commas).
    private static func parseForwardComment(_ trimmed: String, marker: String) -> PortForward? {
        guard trimmed.lowercased().hasPrefix(marker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        let parts = payload.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let spec = String(parts[0])
        let note = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return PortForward(spec: spec, note: note)
    }

    private static func parseOSComment(_ trimmed: String) -> SSHHost.OS? {
        guard trimmed.lowercased().hasPrefix(osMarker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(osMarker.count).trimmingCharacters(in: .whitespaces)
        return SSHHost.OS.allCases.first { $0.rawValue.caseInsensitiveCompare(payload) == .orderedSame }
    }

    private static func parseRemoteAppComment(_ trimmed: String) -> String? {
        guard trimmed.lowercased().hasPrefix(remoteAppMarker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(remoteAppMarker.count).trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }

    private static func parseZoneComment(_ trimmed: String) -> String? {
        guard trimmed.lowercased().hasPrefix(zoneMarker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(zoneMarker.count).trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }

    /// Maps a `# sshCM-tag:` payload to a known `HostTag`. An unrecognized value
    /// yields `nil` (treated as untagged) rather than being surfaced.
    private static func parseTagComment(_ trimmed: String) -> HostTag? {
        guard trimmed.lowercased().hasPrefix(tagMarker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(tagMarker.count).trimmingCharacters(in: .whitespaces)
        return HostTag(rawValue: payload.lowercased())
    }

    /// Favorite is a simple on/off flag, so any `# sshCM-favorite:` line (regardless
    /// of payload) marks the host as favorited. `serializeHost` always writes `yes`.
    private static func parseFavoriteComment(_ trimmed: String) -> Bool {
        trimmed.lowercased().hasPrefix(favoriteMarker.lowercased())
    }

    private static func parseVNCPortComment(_ trimmed: String) -> Int? {
        guard trimmed.lowercased().hasPrefix(vncPortMarker.lowercased()) else { return nil }
        let payload = trimmed.dropFirst(vncPortMarker.count).trimmingCharacters(in: .whitespaces)
        return Int(payload)
    }

    /// SMB is a simple on/off flag, so any `# sshCM-smb:` line (regardless of
    /// payload) marks the host as SMB-enabled. `serializeHost` always writes
    /// `yes`, but we don't require a specific value when reading back.
    private static func parseSMBComment(_ trimmed: String) -> Bool {
        trimmed.lowercased().hasPrefix(smbMarker.lowercased())
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
            // Only accept a real TCP port. An out-of-range or non-numeric value
            // is left as a raw line (round-trips verbatim) rather than surfaced
            // as a typed port — and never reaches `UInt16(port)` in Reachability.
            guard let p = Int(value), (1...65535).contains(p) else { return false }
            host.port = p
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
