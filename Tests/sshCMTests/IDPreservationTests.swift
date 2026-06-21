import Testing
@testable import sshCMModels

// Tests for the ID-preservation mechanism that makes host references stable across
// a file reload. This is the guarantee that prevents the command palette from
// losing the host it is editing when ~/.ssh/config changes on disk.

@Suite("SSHConfigFile – ID preservation")
struct IDPreservationTests {

    @Test func idsPreservedForMatchingPrimaryAlias() {
        let text = "Host alpha\n    HostName alpha.com\nHost beta\n    HostName beta.com\n"
        var file = SSHConfigParser.parse(text)
        let alphaID = file.hosts.first { $0.aliases.first == "alpha" }!.id
        let betaID  = file.hosts.first { $0.aliases.first == "beta"  }!.id

        var reparsed = SSHConfigParser.parse(file.serialize())
        reparsed.preserveIDs(from: file)

        #expect(reparsed.hosts.first { $0.aliases.first == "alpha" }?.id == alphaID)
        #expect(reparsed.hosts.first { $0.aliases.first == "beta"  }?.id == betaID)
    }

    @Test func newHostGetsItsOwnFreshId() {
        let original   = SSHConfigParser.parse("Host old\n    HostName old.com\n")
        let originalID = original.hosts[0].id

        var reparsed = SSHConfigParser.parse("Host old\n    HostName old.com\nHost new\n    HostName new.com\n")
        reparsed.preserveIDs(from: original)

        #expect(reparsed.hosts.first { $0.aliases.first == "old" }?.id == originalID)
        // "new" must not accidentally inherit the old UUID
        let newID = reparsed.hosts.first { $0.aliases.first == "new" }!.id
        #expect(newID != originalID)
    }

    @Test func removedHostDoesNotPolluteSurvivingIds() {
        let text = "Host alpha\n    HostName a.com\nHost beta\n    HostName b.com\n"
        let original = SSHConfigParser.parse(text)
        let betaID   = original.hosts.first { $0.aliases.first == "beta" }!.id

        var reparsed = SSHConfigParser.parse("Host beta\n    HostName b.com\n")
        reparsed.preserveIDs(from: original)

        #expect(reparsed.hosts.first { $0.aliases.first == "beta" }?.id == betaID)
    }

    @Test func duplicatePrimaryAliasConsumedInOrder() {
        // Pathological: two hosts with the same primary alias (invalid config, but
        // the preserver must not crash and must hand out IDs in declaration order).
        var old = SSHConfigFile()
        old.append(host: SSHHost(aliases: ["dup"], hostName: "first.com"))
        old.append(host: SSHHost(aliases: ["dup"], hostName: "second.com"))
        let firstID  = old.hosts[0].id
        let secondID = old.hosts[1].id

        var reparsed = SSHConfigParser.parse(old.serialize())
        reparsed.preserveIDs(from: old)

        #expect(reparsed.hosts[0].id == firstID)
        #expect(reparsed.hosts[1].id == secondID)
    }

    @Test func preserveIdsIsIdempotent() {
        let text = "Host myserver\n    HostName example.com\n"
        var file = SSHConfigParser.parse(text)
        let id = file.hosts[0].id
        file.preserveIDs(from: file)
        #expect(file.hosts[0].id == id)
    }

    @Test func preserveIdsWithEmptyOldFileIsNoop() {
        var file = SSHConfigParser.parse("Host myserver\n    HostName example.com\n")
        let id = file.hosts[0].id
        file.preserveIDs(from: SSHConfigFile())
        // No match → id unchanged
        #expect(file.hosts[0].id == id)
    }
}
