import Foundation
import Darwin

/// Pure, Foundation-only block-computation logic extracted from HostsFilePublisher.
/// These functions have no I/O side effects and can be tested without AppKit or
/// elevated privileges.
enum HostsFileBlock {
    static let beginMarker =
        "# BEGIN sshCM-managed \u{2014} do not edit (managed by sshCM; changes here are overwritten)"
    static let endMarker = "# END sshCM-managed"
    static let beginMarkerPrefix = "# BEGIN sshCM-managed"
    static let endMarkerPrefix   = "# END sshCM-managed"

    // MARK: - Entry computation

    /// One `IP<tab>alias…` line per publishable host.  Aliases that are SSH
    /// patterns (`*`, `?`) or otherwise invalid as hostnames are dropped, and a
    /// given alias is only published once (first host wins).
    static func managedEntries(for hosts: [SSHHost]) -> [String] {
        var claimed = Set<String>()
        var lines: [String] = []
        for host in hosts {
            guard let ip = host.hostName?.trimmingCharacters(in: .whitespaces),
                  isLiteralIP(ip) else { continue }
            let names = host.aliases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { isPublishableHostname($0) && !claimed.contains($0) }
            guard !names.isEmpty else { continue }
            names.forEach { claimed.insert($0) }
            lines.append("\(ip)\t\(names.joined(separator: " "))")
        }
        return lines
    }

    /// Replaces (or removes) the managed block within `current`, leaving all
    /// other lines untouched.
    static func rebuild(current: String, entries: [String]) -> String {
        var lines = current.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.hasPrefix(beginMarkerPrefix) }),
           let end = lines[start...].firstIndex(where: { $0.hasPrefix(endMarkerPrefix) }) {
            lines.removeSubrange(start...end)
            // Collapse the blank line that used to separate the block.
            if start < lines.count, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: start)
            }
        }

        var base = lines.joined(separator: "\n")
        while base.hasSuffix("\n") || base.hasSuffix(" ") || base.hasSuffix("\t") {
            base.removeLast()
        }

        guard !entries.isEmpty else {
            return base.isEmpty ? "" : base + "\n"
        }
        let block = ([beginMarker] + entries + [endMarker]).joined(separator: "\n")
        return base.isEmpty ? block + "\n" : base + "\n\n" + block + "\n"
    }

    // MARK: - Validation

    /// Returns `true` when `value` is a valid IPv4 or IPv6 literal address.
    static func isLiteralIP(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.withCString { cstr in
            var v4 = in_addr()
            if inet_pton(AF_INET, cstr, &v4) == 1 { return true }
            var v6 = in6_addr()
            return inet_pton(AF_INET6, cstr, &v6) == 1
        }
    }

    /// Characters allowed in a hostname / SSH alias written to /etc/hosts.
    static let hostnameAllowedCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")

    /// Returns `true` when `value` is safe to write into `/etc/hosts`:
    /// non-empty, length ≤ 253, only DNS-label characters (no glob/negation chars).
    static func isPublishableHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253 else { return false }
        return value.unicodeScalars.allSatisfy { hostnameAllowedCharacters.contains($0) }
    }
}
