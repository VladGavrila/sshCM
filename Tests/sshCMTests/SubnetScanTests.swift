import Testing
@testable import sshCMModels

@Suite("SubnetScan – IPv4 parsing")
struct SubnetScanIPv4Tests {

    @Test func parsesValidDottedQuad() {
        #expect(SubnetScan.parseIPv4("192.168.1.20") == 0xC0_A8_01_14)
        #expect(SubnetScan.parseIPv4("0.0.0.0") == 0)
        #expect(SubnetScan.parseIPv4("255.255.255.255") == 0xFFFF_FFFF)
    }

    @Test func rejectsMalformed() {
        #expect(SubnetScan.parseIPv4("192.168.1") == nil)        // too few octets
        #expect(SubnetScan.parseIPv4("192.168.1.1.1") == nil)    // too many
        #expect(SubnetScan.parseIPv4("192.168.1.256") == nil)    // octet > 255
        #expect(SubnetScan.parseIPv4("192.168.1.") == nil)       // empty octet
        #expect(SubnetScan.parseIPv4("192.168.1.x") == nil)      // non-numeric
        #expect(SubnetScan.parseIPv4("0x10.0.0.1") == nil)       // hex not allowed
    }

    @Test func roundTripsThroughFormat() {
        for s in ["10.0.0.1", "172.16.254.3", "192.168.100.200"] {
            #expect(SubnetScan.formatIPv4(SubnetScan.parseIPv4(s)!) == s)
        }
    }
}

@Suite("SubnetScan – mask / prefix")
struct SubnetScanMaskTests {

    @Test func maskForPrefixCoversBoundaries() {
        #expect(SubnetScan.maskForPrefix(0) == 0)
        #expect(SubnetScan.maskForPrefix(24) == 0xFFFF_FF00)
        #expect(SubnetScan.maskForPrefix(32) == 0xFFFF_FFFF)
    }

    @Test func prefixForMaskRoundTrips() {
        #expect(SubnetScan.prefixForMask(0xFFFF_FF00) == 24)
        #expect(SubnetScan.prefixForMask(0xFFFF_FFFF) == 32)
        #expect(SubnetScan.prefixForMask(0) == 0)
    }

    @Test func prefixForMaskRejectsNonContiguous() {
        // 255.0.255.0 is not a valid contiguous mask.
        #expect(SubnetScan.prefixForMask(0xFF00_FF00) == nil)
    }
}

@Suite("SubnetScan – CIDR ranges")
struct SubnetScanCIDRTests {

    @Test func slash24ExcludesNetworkAndBroadcast() throws {
        let hosts = try SubnetScan.parseCIDR("192.168.1.0/24").get()
        #expect(hosts.count == 254)
        #expect(hosts.first == "192.168.1.1")
        #expect(hosts.last == "192.168.1.254")
        #expect(!hosts.contains("192.168.1.0"))    // network
        #expect(!hosts.contains("192.168.1.255"))  // broadcast
    }

    @Test func slash30HasTwoHosts() throws {
        let hosts = try SubnetScan.parseCIDR("10.0.0.0/30").get()
        #expect(hosts == ["10.0.0.1", "10.0.0.2"])
    }

    @Test func slash32ReturnsTheSingleAddress() throws {
        // A /32 has no network/broadcast to exclude — the one address is usable.
        let hosts = try SubnetScan.parseCIDR("10.0.0.5/32").get()
        #expect(hosts == ["10.0.0.5"])
    }

    @Test func slash31ReturnsBothAddresses() throws {
        let hosts = try SubnetScan.parseCIDR("10.0.0.4/31").get()
        #expect(hosts == ["10.0.0.4", "10.0.0.5"])
    }

    @Test func normalizesNonZeroHostBits() throws {
        // 192.168.1.42/24 still means the whole .0 subnet.
        let hosts = try SubnetScan.parseCIDR("192.168.1.42/24").get()
        #expect(hosts.count == 254)
        #expect(hosts.first == "192.168.1.1")
    }

    @Test func rejectsMalformedCIDR() {
        #expect(isFailure(SubnetScan.parseCIDR("192.168.1.0/33")))
        #expect(isFailure(SubnetScan.parseCIDR("192.168.1.0/")))
        #expect(isFailure(SubnetScan.parseCIDR("garbage/24")))
    }

    @Test func rejectsOversizedRange() {
        // /16 is 65534 hosts — above the safety cap.
        #expect(isFailure(SubnetScan.parseCIDR("10.0.0.0/16")))
    }
}

@Suite("SubnetScan – dash ranges & dispatch")
struct SubnetScanRangeTests {

    @Test func fullDashRange() throws {
        let hosts = try SubnetScan.parseScanRange("10.0.0.1-10.0.0.4").get()
        #expect(hosts == ["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4"])
    }

    @Test func lastOctetShorthand() throws {
        let hosts = try SubnetScan.parseScanRange("10.0.0.10-12").get()
        #expect(hosts == ["10.0.0.10", "10.0.0.11", "10.0.0.12"])
    }

    @Test func bareIPScansOneHost() throws {
        #expect(try SubnetScan.parseScanRange("10.0.0.7").get() == ["10.0.0.7"])
    }

    @Test func invertedRangeIsRejected() {
        #expect(isFailure(SubnetScan.parseScanRange("10.0.0.10-10.0.0.1")))
    }

    @Test func emptyInputIsRejected() {
        #expect(isFailure(SubnetScan.parseScanRange("   ")))
    }

    @Test func garbageIsRejected() {
        #expect(isFailure(SubnetScan.parseScanRange("not-an-ip")))
    }
}

@Suite("SubnetScan – default range")
struct SubnetScanDefaultRangeTests {

    @Test func buildsCIDRFromAddressAndMask() {
        #expect(SubnetScan.defaultRange(ip: "192.168.1.42", netmask: "255.255.255.0") == "192.168.1.0/24")
        #expect(SubnetScan.defaultRange(ip: "10.1.2.3", netmask: "255.255.0.0") == "10.1.0.0/16")
    }

    @Test func nilOnInvalidMask() {
        #expect(SubnetScan.defaultRange(ip: "192.168.1.42", netmask: "255.0.255.0") == nil)
        #expect(SubnetScan.defaultRange(ip: "bogus", netmask: "255.255.255.0") == nil)
    }
}

// Small helper mirroring the codebase's terse test style.
private func isFailure(_ result: Result<[String], SubnetScan.ParseError>) -> Bool {
    if case .failure = result { return true }
    return false
}
