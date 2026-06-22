import Testing
@testable import sshCMModels

// MARK: - Parsing

@Suite("SSHConfigParser – parsing")
struct ParserTests {

    @Test func emptyStringProducesEmptyFile() {
        #expect(SSHConfigParser.parse("").hosts.isEmpty)
    }

    @Test func singleHostAllKnownKeys() {
        let text = """
        Host myserver
            HostName example.com
            User admin
            Port 2222
            IdentityFile ~/.ssh/id_rsa
            ProxyJump bastion
        """
        let host = SSHConfigParser.parse(text).hosts[0]
        #expect(host.aliases == ["myserver"])
        #expect(host.hostName == "example.com")
        #expect(host.user == "admin")
        #expect(host.port == 2222)
        #expect(host.identityFile == "~/.ssh/id_rsa")
        #expect(host.proxyJump == "bastion")
    }

    @Test func multipleAliasesOnOneLine() {
        let text = "Host web1 web2 web3\n    HostName webserver.example.com\n"
        #expect(SSHConfigParser.parse(text).hosts[0].aliases == ["web1", "web2", "web3"])
    }

    @Test func multipleHostBlocks() {
        let text = """
        Host alpha
            HostName alpha.example.com
        Host beta
            HostName beta.example.com
        """
        let hosts = SSHConfigParser.parse(text).hosts
        #expect(hosts.count == 2)
        #expect(hosts[0].aliases.first == "alpha")
        #expect(hosts[1].aliases.first == "beta")
    }

    @Test func unknownKeysFallToRawLines() {
        let text = """
        Host myserver
            HostName example.com
            ForwardAgent yes
            ServerAliveInterval 30
        """
        let host = SSHConfigParser.parse(text).hosts[0]
        #expect(host.rawLines.contains("    ForwardAgent yes"))
        #expect(host.rawLines.contains("    ServerAliveInterval 30"))
        #expect(host.hostName == "example.com")
    }

    @Test func globalDirectivesPreserved() {
        let text = "ServerAliveInterval 60\n\nHost myserver\n    HostName example.com\n"
        #expect(SSHConfigParser.parse(text).serialize().contains("ServerAliveInterval 60"))
    }

    @Test func commentsPreservedGlobalAndInline() {
        let text = "# Global comment\n\nHost myserver\n    # inline comment\n    HostName example.com\n"
        let serialized = SSHConfigParser.parse(text).serialize()
        #expect(serialized.contains("# Global comment"))
        #expect(serialized.contains("# inline comment"))
    }

    @Test func matchBlockPreservedVerbatim() {
        let text = """
        Host myserver
            HostName example.com

        Match host *.internal
            StrictHostKeyChecking no
            ProxyCommand /usr/bin/nc -X connect -x proxy:8080 %h %p

        Host other
            HostName other.example.com
        """
        let file = SSHConfigParser.parse(text)
        #expect(file.hosts.count == 2)
        let serialized = file.serialize()
        #expect(serialized.contains("Match host *.internal"))
        #expect(serialized.contains("StrictHostKeyChecking no"))
        #expect(serialized.contains("ProxyCommand /usr/bin/nc"))
    }

    // Validates the invariant that Host always starts a fresh stanza.
    // This test covers the `|| true` guard in the parser – which must remain
    // correct after any restructuring of the condition.
    @Test func hostLineAfterMatchBlockStartsNewHost() {
        let text = """
        Match host *.internal
            StrictHostKeyChecking no
        Host myserver
            HostName example.com
        """
        let file = SSHConfigParser.parse(text)
        #expect(file.hosts.count == 1)
        #expect(file.hosts[0].aliases.first == "myserver")
        #expect(file.serialize().contains("Match host *.internal"))
    }

    @Test func equalSignKeyValueSyntax() {
        let text = "Host myserver\n    HostName=example.com\n    User=admin\n    Port=2222\n"
        let host = SSHConfigParser.parse(text).hosts[0]
        #expect(host.hostName == "example.com")
        #expect(host.user == "admin")
        #expect(host.port == 2222)
    }

    @Test func quotedValueIsUnquoted() {
        let text = "Host myserver\n    IdentityFile \"/Users/me/.ssh/my key\"\n"
        #expect(SSHConfigParser.parse(text).hosts[0].identityFile == "/Users/me/.ssh/my key")
    }

    @Test func invalidPortFallsToRawLine() {
        let text = "Host myserver\n    HostName example.com\n    Port notanumber\n"
        let host = SSHConfigParser.parse(text).hosts[0]
        #expect(host.port == nil)
        #expect(host.rawLines.contains("    Port notanumber"))
    }

    @Test func tabSeparatedKeyValueParsed() {
        // OpenSSH allows tabs as key-value separators. Previously this fell to rawLines.
        let text = "Host myserver\n\tHostName\texample.com\n"
        #expect(SSHConfigParser.parse(text).hosts[0].hostName == "example.com")
    }

    @Test func caseInsensitiveKeywords() {
        let text = "host myserver\n    hostname example.com\n    USER admin\n    PORT 22\n"
        let host = SSHConfigParser.parse(text).hosts[0]
        #expect(host.aliases.first == "myserver")
        #expect(host.hostName == "example.com")
        #expect(host.user == "admin")
        #expect(host.port == 22)
    }

    @Test func blankLinesBetweenHostsPreserved() {
        let text = "Host alpha\n    HostName alpha.com\n\nHost beta\n    HostName beta.com\n"
        let serialized = SSHConfigParser.parse(text).serialize()
        #expect(serialized == text)
    }
}

// MARK: - sshCM metadata markers

@Suite("SSHConfigParser – sshCM metadata markers")
struct MetadataMarkerTests {

    @Test func markerConstantsHaveExpectedValues() {
        #expect(SSHConfigParser.searchAliasesMarker == "# sshCM-aliases:")
        #expect(SSHConfigParser.alternateUsersMarker == "# sshCM-users:")
        #expect(SSHConfigParser.localForwardMarker == "# sshCM-localforward:")
        #expect(SSHConfigParser.remoteForwardMarker == "# sshCM-remoteforward:")
        #expect(SSHConfigParser.osMarker == "# sshCM-os:")
        #expect(SSHConfigParser.remoteAppMarker == "# sshCM-remoteapp:")
        #expect(SSHConfigParser.vncPortMarker == "# sshCM-vncport:")
    }

    @Test func remoteAppMarkerParsed() {
        let text = "Host myserver\n    # sshCM-remoteapp: RustDesk\n"
        #expect(SSHConfigParser.parse(text).hosts[0].remoteApp == "RustDesk")
    }

    @Test func missingRemoteAppMarkerLeavesRemoteAppUnset() {
        let text = "Host myserver\n    HostName example.com\n"
        #expect(SSHConfigParser.parse(text).hosts[0].remoteApp == nil)
    }

    @Test func macOSMarkerParsed() {
        let text = "Host myserver\n    # sshCM-os: macOS\n"
        #expect(SSHConfigParser.parse(text).hosts[0].os == .macOS)
    }

    @Test func linuxMarkerParsed() {
        let text = "Host myserver\n    # sshCM-os: linux\n"
        #expect(SSHConfigParser.parse(text).hosts[0].os == .linux)
    }

    @Test func osMarkerLookupCaseInsensitive() {
        let text = "Host myserver\n    # sshCM-os: MACOS\n"
        #expect(SSHConfigParser.parse(text).hosts[0].os == .macOS)
    }

    @Test func missingOSMarkerLeavesOSUnset() {
        let text = "Host myserver\n    HostName example.com\n"
        #expect(SSHConfigParser.parse(text).hosts[0].os == nil)
    }

    @Test func vncPortMarkerParsed() {
        let text = "Host myserver\n    # sshCM-vncport: 5901\n"
        #expect(SSHConfigParser.parse(text).hosts[0].vncPort == 5901)
    }

    @Test func missingVNCPortMarkerLeavesVNCPortUnset() {
        let text = "Host myserver\n    HostName example.com\n"
        #expect(SSHConfigParser.parse(text).hosts[0].vncPort == nil)
    }

    @Test func searchAliasesParsed() {
        let text = "Host myserver\n    # sshCM-aliases: alias1, alias2, alias3\n    HostName example.com\n"
        #expect(SSHConfigParser.parse(text).hosts[0].searchAliases == ["alias1", "alias2", "alias3"])
    }

    @Test func alternateUsersParsed() {
        let text = "Host myserver\n    # sshCM-users: root, deploy, ci\n"
        #expect(SSHConfigParser.parse(text).hosts[0].alternateUsers == ["root", "deploy", "ci"])
    }

    @Test func localForwardWithNoteParsed() {
        let text = "Host myserver\n    # sshCM-localforward: 8080:localhost:8080 Web server tunnel\n"
        let fwd = SSHConfigParser.parse(text).hosts[0].localForwards[0]
        #expect(fwd.spec == "8080:localhost:8080")
        #expect(fwd.note == "Web server tunnel")
    }

    @Test func remoteForwardWithoutNoteParsed() {
        let text = "Host myserver\n    # sshCM-remoteforward: 9090:localhost:9090\n"
        let fwd = SSHConfigParser.parse(text).hosts[0].remoteForwards[0]
        #expect(fwd.spec == "9090:localhost:9090")
        #expect(fwd.note == "")
    }

    @Test func multipleForwardMarkersAllParsed() {
        let text = """
        Host myserver
            # sshCM-localforward: 8080:localhost:8080 Web
            # sshCM-localforward: 5432:localhost:5432 DB
            # sshCM-remoteforward: 9090:localhost:9090 Metrics
        """
        let host = SSHConfigParser.parse(text).hosts[0]
        #expect(host.localForwards.count == 2)
        #expect(host.remoteForwards.count == 1)
    }

    @Test func markerLookupCaseInsensitive() {
        let text = "Host myserver\n    # SSHCM-ALIASES: alias1\n"
        #expect(SSHConfigParser.parse(text).hosts[0].searchAliases == ["alias1"])
    }

    @Test func markersNotLeakedAsRawLines() {
        let text = "Host myserver\n    # sshCM-aliases: a\n    # sshCM-users: root\n    HostName x.com\n"
        let host = SSHConfigParser.parse(text).hosts[0]
        #expect(host.rawLines.isEmpty)
    }
}

// MARK: - Round-trip

@Suite("SSHConfigParser – round-trip")
struct RoundTripTests {

    @Test func singleHostRoundTrip() {
        let text = "Host myserver\n    HostName example.com\n    User admin\n    Port 2222\n"
        let reparsed = SSHConfigParser.parse(SSHConfigParser.parse(text).serialize())
        let host = reparsed.hosts[0]
        #expect(host.aliases == ["myserver"])
        #expect(host.hostName == "example.com")
        #expect(host.user == "admin")
        #expect(host.port == 2222)
    }

    @Test func rawLinesRoundTrip() {
        let text = "Host myserver\n    HostName example.com\n    ForwardAgent yes\n    Compression yes\n"
        let file = SSHConfigParser.parse(text)
        let reparsed = SSHConfigParser.parse(file.serialize())
        #expect(reparsed.hosts[0].rawLines == file.hosts[0].rawLines)
    }

    @Test func searchAliasesRoundTrip() {
        let text = "Host myserver\n    # sshCM-aliases: alias1, alias2\n    HostName example.com\n"
        let file = SSHConfigParser.parse(text)
        #expect(SSHConfigParser.parse(file.serialize()).hosts[0].searchAliases == ["alias1", "alias2"])
    }

    @Test func alternateUsersRoundTrip() {
        let text = "Host myserver\n    # sshCM-users: root, deploy\n"
        let file = SSHConfigParser.parse(text)
        #expect(SSHConfigParser.parse(file.serialize()).hosts[0].alternateUsers == ["root", "deploy"])
    }

    @Test func portForwardsRoundTrip() {
        let text = "Host myserver\n    # sshCM-localforward: 8080:localhost:8080 Web\n    # sshCM-remoteforward: 9090:localhost:9090\n"
        let file = SSHConfigParser.parse(text)
        let reparsed = SSHConfigParser.parse(file.serialize())
        #expect(reparsed.hosts[0].localForwards == file.hosts[0].localForwards)
        #expect(reparsed.hosts[0].remoteForwards == file.hosts[0].remoteForwards)
    }

    @Test func vncPortRoundTrip() {
        let text = "Host myserver\n    # sshCM-vncport: 5901\n"
        let file = SSHConfigParser.parse(text)
        let reparsed = SSHConfigParser.parse(file.serialize())
        #expect(reparsed.hosts[0].vncPort == 5901)
    }

    @Test func remoteAppRoundTrip() {
        let text = "Host myserver\n    # sshCM-remoteapp: RustDesk\n"
        let file = SSHConfigParser.parse(text)
        #expect(SSHConfigParser.parse(file.serialize()).hosts[0].remoteApp == "RustDesk")
    }

    // The legacy `# sshCM-os:` marker is only ever read for one-time migration —
    // it must never be written back out, even though it's still parsed.
    @Test func legacyOSMarkerIsNotReSerialized() {
        let text = "Host myserver\n    # sshCM-os: linux\n"
        let file = SSHConfigParser.parse(text)
        #expect(file.hosts[0].os == .linux)
        #expect(!file.serialize().contains(SSHConfigParser.osMarker))
    }

    @Test func migrateLegacyOSMarkersMapsMacOSToScreenSharing() {
        var file = SSHConfigParser.parse("Host myserver\n    # sshCM-os: macOS\n")
        file.migrateLegacyOSMarkers(linuxAppPathConfigured: false)
        #expect(file.hosts[0].remoteApp == RemoteAccessApp.screenSharingName)
        #expect(file.hosts[0].os == nil)
    }

    @Test func migrateLegacyOSMarkersMapsLinuxOnlyWhenAppConfigured() {
        var withApp = SSHConfigParser.parse("Host myserver\n    # sshCM-os: linux\n")
        withApp.migrateLegacyOSMarkers(linuxAppPathConfigured: true)
        #expect(withApp.hosts[0].remoteApp == RemoteAccessApp.legacyLinuxAppName)

        var withoutApp = SSHConfigParser.parse("Host myserver\n    # sshCM-os: linux\n")
        withoutApp.migrateLegacyOSMarkers(linuxAppPathConfigured: false)
        #expect(withoutApp.hosts[0].remoteApp == nil)
    }

    @Test func migrateLegacyOSMarkersDoesNotOverrideExistingRemoteApp() {
        var file = SSHConfigParser.parse("Host myserver\n    # sshCM-os: macOS\n    # sshCM-remoteapp: TigerVNC\n")
        file.migrateLegacyOSMarkers(linuxAppPathConfigured: false)
        #expect(file.hosts[0].remoteApp == "TigerVNC")
    }

    // The default VNC port (5900) is never written back out, matching the
    // "only persist if non-default" convention used elsewhere for optional fields.
    @Test func defaultVNCPortIsNotSerialized() {
        var host = SSHHost(aliases: ["myserver"])
        host.vncPort = 5900
        var file = SSHConfigFile()
        file.append(host: host)
        #expect(!file.serialize().contains(SSHConfigParser.vncPortMarker))
    }

    @Test func nonDefaultVNCPortIsSerialized() {
        var host = SSHHost(aliases: ["myserver"])
        host.vncPort = 5901
        var file = SSHConfigFile()
        file.append(host: host)
        #expect(file.serialize().contains("# sshCM-vncport: 5901"))
    }

    @Test func multipleHostsRoundTrip() {
        let text = "Host alpha\n    HostName alpha.example.com\n\nHost beta\n    HostName beta.example.com\n"
        let reparsed = SSHConfigParser.parse(SSHConfigParser.parse(text).serialize())
        #expect(reparsed.hosts.count == 2)
        #expect(reparsed.hosts[0].hostName == "alpha.example.com")
        #expect(reparsed.hosts[1].hostName == "beta.example.com")
    }

    @Test func serializeAlwaysEndsWithNewline() {
        #expect(SSHConfigParser.parse("Host x\n    HostName y\n").serialize().hasSuffix("\n"))
    }

    @Test func emptyFileSerializesToSingleNewline() {
        #expect(SSHConfigFile().serialize() == "\n")
    }
}
