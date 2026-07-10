import Foundation

/// Pure logic for zone declarations: validation, duplicate detection, and
/// reconciling the user-declared list against zones actually found on hosts.
/// No `UserDefaults`/Observation here — `ZonesStore` owns persistence.
enum ZoneCatalog {
    /// Trimmed, non-empty, and restricted to the same character set as an SSH
    /// alias / `/etc/hosts` hostname — no spaces or special characters, so a
    /// zone name stays a safe, unambiguous token everywhere it's displayed
    /// (search haystack, config marker, toolbar filter).
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, HostsFileBlock.isPublishableHostname(trimmed) else { return nil }
        return trimmed
    }

    /// Strips every character not allowed in a zone name (the same set
    /// enforced by `normalized`), for live-filtering a text field as the user
    /// types — mirrors the alias field's input filter.
    static func sanitizeInput(_ value: String) -> String {
        String(String.UnicodeScalarView(
            value.unicodeScalars.filter { HostsFileBlock.hostnameAllowedCharacters.contains($0) }
        ))
    }

    /// Case-insensitive duplicate check against existing declarations.
    static func isDuplicate(_ name: String, in zones: [String]) -> Bool {
        zones.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Declared list ∪ zones found on hosts, preserving declared order,
    /// auto-appending unknown host zones in first-seen order.
    static func reconciled(declared: [String], hostZones: [String]) -> [String] {
        var result = declared
        var seen = Set(declared.map { $0.lowercased() })
        for zone in hostZones {
            let key = zone.lowercased()
            if seen.insert(key).inserted {
                result.append(zone)
            }
        }
        return result
    }
}
