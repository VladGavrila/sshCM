import Testing
@testable import sshCMModels

@Suite("SSHHost – ProxyJump alias extraction")
struct JumpHostTests {

    @Test func simpleProxyJump() {
        let host = SSHHost(aliases: ["target"], proxyJump: "bastion")
        #expect(SSHHost.jumpHostAliases(in: [host]).contains("bastion"))
    }

    @Test func chainedJumpsAllExtracted() {
        let host = SSHHost(aliases: ["target"], proxyJump: "jump1,jump2,jump3")
        let aliases = SSHHost.jumpHostAliases(in: [host])
        #expect(aliases.contains("jump1"))
        #expect(aliases.contains("jump2"))
        #expect(aliases.contains("jump3"))
    }

    @Test func userPrefixStripped() {
        let host = SSHHost(aliases: ["target"], proxyJump: "admin@bastion")
        let aliases = SSHHost.jumpHostAliases(in: [host])
        #expect(aliases.contains("bastion"))
        #expect(!aliases.contains("admin@bastion"))
    }

    @Test func portSuffixStripped() {
        let host = SSHHost(aliases: ["target"], proxyJump: "bastion:2222")
        let aliases = SSHHost.jumpHostAliases(in: [host])
        #expect(aliases.contains("bastion"))
        #expect(!aliases.contains("bastion:2222"))
    }

    @Test func userAndPortBothStripped() {
        let host = SSHHost(aliases: ["target"], proxyJump: "admin@bastion:2222")
        let aliases = SSHHost.jumpHostAliases(in: [host])
        #expect(aliases.contains("bastion"))
        #expect(!aliases.contains("admin@bastion:2222"))
    }

    @Test func nilProxyJumpProducesEmptySet() {
        let host = SSHHost(aliases: ["target"])
        #expect(SSHHost.jumpHostAliases(in: [host]).isEmpty)
    }

    @Test func emptyProxyJumpProducesEmptySet() {
        let host = SSHHost(aliases: ["target"], proxyJump: "")
        #expect(SSHHost.jumpHostAliases(in: [host]).isEmpty)
    }

    @Test func mixedHopFormats() {
        let host = SSHHost(aliases: ["target"], proxyJump: "jump1,user@jump2:2222,jump3")
        let aliases = SSHHost.jumpHostAliases(in: [host])
        #expect(aliases == ["jump1", "jump2", "jump3"])
    }

    @Test func multipleHostsResultsUnioned() {
        let hosts = [
            SSHHost(aliases: ["target1"], proxyJump: "bastion"),
            SSHHost(aliases: ["target2"], proxyJump: "bastion,jump2")
        ]
        let aliases = SSHHost.jumpHostAliases(in: hosts)
        #expect(aliases.contains("bastion"))
        #expect(aliases.contains("jump2"))
        // Set deduplication: bastion appears in both but only once in result
        #expect(aliases.count == 2)
    }

    @Test func hostsWithoutProxyJumpDontContribute() {
        let hosts = [
            SSHHost(aliases: ["noJump"]),
            SSHHost(aliases: ["withJump"], proxyJump: "bastion")
        ]
        let aliases = SSHHost.jumpHostAliases(in: hosts)
        #expect(aliases == ["bastion"])
    }

    @Test func emptyHostListProducesEmptySet() {
        #expect(SSHHost.jumpHostAliases(in: []).isEmpty)
    }
}
