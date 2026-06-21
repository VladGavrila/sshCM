import Testing
@testable import sshCMModels

@Suite("HostsFileBlock – IP detection")
struct HostsFileBlockIPTests {

    @Test func validIPv4Detected() {
        #expect(HostsFileBlock.isLiteralIP("1.2.3.4"))
        #expect(HostsFileBlock.isLiteralIP("192.168.1.100"))
        #expect(HostsFileBlock.isLiteralIP("10.0.0.1"))
        #expect(HostsFileBlock.isLiteralIP("255.255.255.0"))
    }

    @Test func validIPv6Detected() {
        #expect(HostsFileBlock.isLiteralIP("::1"))
        #expect(HostsFileBlock.isLiteralIP("2001:db8::1"))
        #expect(HostsFileBlock.isLiteralIP("fe80::1"))
    }

    @Test func dnsNameNotIP() {
        #expect(!HostsFileBlock.isLiteralIP("example.com"))
        #expect(!HostsFileBlock.isLiteralIP("my-server"))
        #expect(!HostsFileBlock.isLiteralIP(""))
    }
}

@Suite("HostsFileBlock – hostname validation")
struct HostsFileBlockHostnameTests {

    @Test func validHostnameAccepted() {
        #expect(HostsFileBlock.isPublishableHostname("my-server"))
        #expect(HostsFileBlock.isPublishableHostname("web01"))
        #expect(HostsFileBlock.isPublishableHostname("prod.internal"))
    }

    @Test func wildcardRejected() {
        #expect(!HostsFileBlock.isPublishableHostname("*.internal"))
        #expect(!HostsFileBlock.isPublishableHostname("?server"))
    }

    @Test func spaceRejected() {
        #expect(!HostsFileBlock.isPublishableHostname("my server"))
    }

    @Test func emptyRejected() {
        #expect(!HostsFileBlock.isPublishableHostname(""))
    }
}

@Suite("HostsFileBlock – managed entries")
struct HostsFileBlockEntriesTests {

    @Test func onlyLiteralIPsPublished() {
        let hosts = [
            SSHHost(aliases: ["dns-host"],  hostName: "example.com"),
            SSHHost(aliases: ["ip-host"],   hostName: "1.2.3.4")
        ]
        let entries = HostsFileBlock.managedEntries(for: hosts)
        #expect(entries.count == 1)
        #expect(entries[0].contains("1.2.3.4"))
        #expect(entries[0].contains("ip-host"))
    }

    @Test func wildcardAliasNotPublished() {
        let host = SSHHost(aliases: ["*.internal"], hostName: "10.0.0.1")
        #expect(HostsFileBlock.managedEntries(for: [host]).isEmpty)
    }

    @Test func multipleAliasesCombinedOnOneLine() {
        let host = SSHHost(aliases: ["web", "web-01", "web.prod"], hostName: "10.10.0.1")
        let entries = HostsFileBlock.managedEntries(for: [host])
        #expect(entries.count == 1)
        #expect(entries[0].hasPrefix("10.10.0.1\t"))
        #expect(entries[0].contains("web"))
        #expect(entries[0].contains("web-01"))
    }

    @Test func duplicateAliasManagedByFirstHost() {
        let hosts = [
            SSHHost(aliases: ["server"], hostName: "1.1.1.1"),
            SSHHost(aliases: ["server"], hostName: "2.2.2.2")
        ]
        let entries = HostsFileBlock.managedEntries(for: hosts)
        #expect(entries.count == 1)
        #expect(entries[0].hasPrefix("1.1.1.1\t"))
    }

    @Test func hostsWithoutIPProduceNoEntries() {
        let hosts = [SSHHost(aliases: ["noop"]), SSHHost(aliases: ["other"], hostName: nil)]
        #expect(HostsFileBlock.managedEntries(for: hosts).isEmpty)
    }
}

@Suite("HostsFileBlock – rebuild")
struct HostsFileBlockRebuildTests {

    @Test func appendsBlockToEmptyFile() {
        let result = HostsFileBlock.rebuild(current: "", entries: ["1.2.3.4\tserver"])
        #expect(result.contains(HostsFileBlock.beginMarker))
        #expect(result.contains("1.2.3.4\tserver"))
        #expect(result.contains(HostsFileBlock.endMarker))
    }

    @Test func removesBlockWhenEntriesEmpty() {
        let withBlock = """
        127.0.0.1\tlocalhost
        \(HostsFileBlock.beginMarker)
        1.2.3.4\tserver
        \(HostsFileBlock.endMarker)
        """
        let result = HostsFileBlock.rebuild(current: withBlock, entries: [])
        #expect(!result.contains(HostsFileBlock.beginMarker))
        #expect(!result.contains("1.2.3.4"))
        #expect(result.contains("127.0.0.1\tlocalhost"))
    }

    @Test func replacesExistingBlock() {
        let old = """
        127.0.0.1\tlocalhost
        \(HostsFileBlock.beginMarker)
        1.1.1.1\told
        \(HostsFileBlock.endMarker)
        """
        let result = HostsFileBlock.rebuild(current: old, entries: ["2.2.2.2\tnew"])
        #expect(!result.contains("1.1.1.1\told"))
        #expect(result.contains("2.2.2.2\tnew"))
        #expect(result.contains("127.0.0.1\tlocalhost"))
    }

    @Test func emptyEntriesOnEmptyFileProducesEmpty() {
        #expect(HostsFileBlock.rebuild(current: "", entries: []) == "")
    }
}
