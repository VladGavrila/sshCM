import Foundation

/// Pure IPv4 subnet math for the LAN host-discovery scan. Foundation-only (no
/// Darwin/Network imports) so it lives in the SPM package and is unit-tested.
/// Everything is dotted-quad IPv4; malformed input returns a `.failure` rather
/// than trapping (a hand-typed range must never crash the app).
enum SubnetScan {
    /// The largest number of candidate addresses a single scan may enumerate.
    /// A fat-fingered `/8` would otherwise expand to ~16M probes; anything above
    /// this is rejected so the UI can tell the user to narrow the range.
    static let maxScanSize = 1024

    struct ParseError: Error, Equatable {
        let message: String
    }

    // MARK: - IPv4 <-> UInt32

    /// Parses a dotted-quad IPv4 string into its 32-bit value, or `nil` if it
    /// isn't exactly four ASCII 0–255 octets. Deliberately strict: no hex, no
    /// unicode digits, no shorthand.
    static func parseIPv4(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard part.count >= 1, part.count <= 3,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let octet = UInt32(part), octet <= 255 else { return nil }
            result = (result << 8) | octet
        }
        return result
    }

    static func formatIPv4(_ value: UInt32) -> String {
        "\((value >> 24) & 0xff).\((value >> 16) & 0xff).\((value >> 8) & 0xff).\(value & 0xff)"
    }

    // MARK: - Netmask / prefix

    /// The 32-bit mask for a CIDR prefix length (`24` -> `255.255.255.0`).
    static func maskForPrefix(_ prefix: Int) -> UInt32 {
        prefix <= 0 ? 0 : (prefix >= 32 ? ~UInt32(0) : (~UInt32(0)) << (32 - prefix))
    }

    /// The CIDR prefix length for a mask, or `nil` if the mask isn't a valid
    /// contiguous run of ones (e.g. `255.0.255.0`).
    static func prefixForMask(_ mask: UInt32) -> Int? {
        for p in 0...32 where maskForPrefix(p) == mask { return p }
        return nil
    }

    // MARK: - Range parsing

    /// Parses a user-typed scan range. Accepts a bare IP (`10.0.0.4`), CIDR
    /// (`192.168.1.0/24`), or a start–end range (`10.0.0.1-10.0.0.50`, or the
    /// last-octet shorthand `10.0.0.1-50`). Returns the ordered candidate IPs, or
    /// a `.failure` with a message the sheet can surface inline.
    static func parseScanRange(_ text: String) -> Result<[String], ParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .failure(ParseError(message: "Enter a network range to scan."))
        }
        if trimmed.contains("/") { return parseCIDR(trimmed) }
        if trimmed.contains("-") { return parseDashRange(trimmed) }
        if let ip = parseIPv4(trimmed) { return .success([formatIPv4(ip)]) }
        return .failure(ParseError(
            message: "Not a valid IP, CIDR (192.168.1.0/24), or range (192.168.1.1-192.168.1.50)."
        ))
    }

    static func parseCIDR(_ text: String) -> Result<[String], ParseError> {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let ip = parseIPv4(parts[0].trimmingCharacters(in: .whitespaces)),
              let prefix = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              prefix >= 0, prefix <= 32 else {
            return .failure(ParseError(message: "Not a valid CIDR (e.g. 192.168.1.0/24)."))
        }
        return hosts(ip: ip, mask: maskForPrefix(prefix))
    }

    static func parseDashRange(_ text: String) -> Result<[String], ParseError> {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = parseIPv4(parts[0].trimmingCharacters(in: .whitespaces)) else {
            return .failure(ParseError(message: "Range must look like 192.168.1.1-192.168.1.50."))
        }
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
        let end: UInt32
        if let full = parseIPv4(endText) {
            end = full
        } else if endText.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let lastOctet = UInt32(endText), lastOctet <= 255 {
            // Last-octet shorthand: `10.0.0.1-50` means through 10.0.0.50.
            end = (start & 0xffff_ff00) | lastOctet
        } else {
            return .failure(ParseError(message: "Range end isn't a valid IP or last octet."))
        }
        return range(lo: start, hi: end)
    }

    // MARK: - Host enumeration

    /// The scannable hosts in a subnet given an address + mask: the usable range
    /// with the network and broadcast addresses excluded (a `/31` or `/32` block
    /// has no such reserved addresses, so every address is returned).
    static func hosts(ip: UInt32, mask: UInt32) -> Result<[String], ParseError> {
        let network = ip & mask
        let broadcast = network | ~mask
        if broadcast > network + 1 {
            return range(lo: network + 1, hi: broadcast - 1)
        }
        return range(lo: network, hi: broadcast)
    }

    /// The prefill range string for a detected interface address + mask, e.g.
    /// `("192.168.1.42", "255.255.255.0")` -> `"192.168.1.0/24"`. `nil` when the
    /// mask isn't a valid contiguous prefix.
    static func defaultRange(ip: String, netmask: String) -> String? {
        guard let ipVal = parseIPv4(ip), let maskVal = parseIPv4(netmask),
              let prefix = prefixForMask(maskVal) else { return nil }
        return "\(formatIPv4(ipVal & maskVal))/\(prefix)"
    }

    /// Materializes an inclusive `[lo, hi]` address range as strings, rejecting
    /// an inverted range or one larger than `maxScanSize`. The loop avoids
    /// `stride`, which would overflow at `255.255.255.255`.
    private static func range(lo: UInt32, hi: UInt32) -> Result<[String], ParseError> {
        guard lo <= hi else {
            return .failure(ParseError(message: "The start of the range is after its end."))
        }
        let count = UInt64(hi) - UInt64(lo) + 1
        guard count <= UInt64(maxScanSize) else {
            return .failure(ParseError(
                message: "That range covers \(count) addresses — narrow it to \(maxScanSize) or fewer."
            ))
        }
        var out: [String] = []
        out.reserveCapacity(Int(count))
        var current = lo
        while true {
            out.append(formatIPv4(current))
            if current == hi { break }
            current += 1
        }
        return .success(out)
    }
}
