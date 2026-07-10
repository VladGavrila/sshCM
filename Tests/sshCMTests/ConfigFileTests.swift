import Foundation
import Testing
@testable import sshCMModels

@Suite("SSHConfigFile – CRUD")
struct ConfigFileTests {

    @Test func appendSingleHost() {
        var file = SSHConfigFile()
        let host = SSHHost(aliases: ["myserver"], hostName: "example.com")
        file.append(host: host)
        #expect(file.hosts.count == 1)
        #expect(file.hosts[0].hostName == "example.com")
    }

    @Test func appendToEmptyFileAddsNoBlankSeparator() {
        var file = SSHConfigFile()
        file.append(host: SSHHost(aliases: ["only"]))
        #expect(file.blocks.count == 1)
    }

    @Test func appendSecondHostInsertsSeparatorBlank() {
        var file = SSHConfigFile()
        file.append(host: SSHHost(aliases: ["alpha"]))
        file.append(host: SSHHost(aliases: ["beta"]))
        // [host(alpha), raw(""), host(beta)]
        #expect(file.blocks.count == 3)
    }

    @Test func appendToFileAlreadyEndingWithBlankAddsNoExtra() {
        var file = SSHConfigFile(blocks: [.raw("")])
        file.append(host: SSHHost(aliases: ["myserver"]))
        // [raw(""), host(myserver)] – no second blank
        #expect(file.blocks.count == 2)
    }

    @Test func removeHostById() {
        var file = SSHConfigFile()
        let host = SSHHost(aliases: ["myserver"], hostName: "example.com")
        file.append(host: host)
        file.remove(id: host.id)
        #expect(file.hosts.isEmpty)
    }

    @Test func removeCleansUpBlankSeparatorAfterHost() {
        var file = SSHConfigFile()
        let host1 = SSHHost(aliases: ["alpha"])
        let host2 = SSHHost(aliases: ["beta"])
        file.append(host: host1)
        file.append(host: host2)
        // [host(alpha), raw(""), host(beta)]
        file.remove(id: host1.id)
        // raw("") at idx 0 is also removed → [host(beta)]
        #expect(file.hosts.count == 1)
        #expect(file.blocks.count == 1)
    }

    @Test func removeNonexistentIdIsNoop() {
        var file = SSHConfigFile()
        file.append(host: SSHHost(aliases: ["myserver"]))
        file.remove(id: UUID())
        #expect(file.hosts.count == 1)
    }

    @Test func updateHostById() {
        var file = SSHConfigFile()
        var host = SSHHost(aliases: ["myserver"], hostName: "example.com", user: "admin")
        file.append(host: host)
        host.user = "root"
        file.update(host)
        #expect(file.hosts[0].user == "root")
    }

    @Test func updatePreservesOtherHosts() {
        var file = SSHConfigFile()
        var alpha = SSHHost(aliases: ["alpha"], hostName: "a.com")
        let beta = SSHHost(aliases: ["beta"], hostName: "b.com")
        file.append(host: alpha)
        file.append(host: beta)
        alpha.hostName = "new-a.com"
        file.update(alpha)
        #expect(file.hosts.first { $0.aliases.first == "alpha" }?.hostName == "new-a.com")
        #expect(file.hosts.first { $0.aliases.first == "beta" }?.hostName == "b.com")
    }

    @Test func updateNonexistentIdIsNoop() {
        var file = SSHConfigFile()
        file.append(host: SSHHost(aliases: ["myserver"]))
        file.update(SSHHost(aliases: ["ghost"]))
        #expect(file.hosts.count == 1)
        #expect(file.hosts[0].aliases.first == "myserver")
    }

    @Test func hostsPropertyFiltersRawBlocks() {
        let file = SSHConfigFile(blocks: [
            .raw("# comment"),
            .host(SSHHost(aliases: ["alpha"])),
            .raw(""),
            .host(SSHHost(aliases: ["beta"]))
        ])
        #expect(file.hosts.count == 2)
        #expect(file.hosts[0].aliases.first == "alpha")
        #expect(file.hosts[1].aliases.first == "beta")
    }

    @Test func appendedHostAppearsInSerializedOutput() {
        var file = SSHConfigFile()
        file.append(host: SSHHost(aliases: ["myserver"], hostName: "example.com", user: "admin", port: 22))
        let serialized = file.serialize()
        #expect(serialized.contains("Host myserver"))
        #expect(serialized.contains("HostName example.com"))
        #expect(serialized.contains("User admin"))
        #expect(serialized.contains("Port 22"))
    }

    @Test func zoneMarkerSerializesInStablePositionAfterOtherMarkers() {
        var host = SSHHost(aliases: ["myserver"], hostName: "example.com")
        host.allowsSMB = true
        host.zone = "home"
        var file = SSHConfigFile()
        file.append(host: host)
        let serialized = file.serialize()
        let smbIdx = serialized.range(of: SSHConfigParser.smbMarker)!.lowerBound
        let zoneIdx = serialized.range(of: SSHConfigParser.zoneMarker)!.lowerBound
        let hostNameIdx = serialized.range(of: "HostName")!.lowerBound
        #expect(smbIdx < zoneIdx)
        #expect(zoneIdx < hostNameIdx)
    }

    @Test func updateHostZonePersistsThroughMutation() {
        var file = SSHConfigFile()
        var host = SSHHost(aliases: ["myserver"])
        file.append(host: host)
        host.zone = "aws"
        file.update(host)
        #expect(file.hosts[0].zone == "aws")
        #expect(file.serialize().contains("# sshCM-zone: aws"))
    }

    // Simulates ConfigStore.updateAll's batched-rewrite loop (which itself lives
    // in the app target and can't be SPM-tested): rename a zone across every
    // member host, then serialize once.
    @Test func renamingZoneAcrossMultipleHostsBatchesIntoOneSerialize() {
        var file = SSHConfigFile()
        var alpha = SSHHost(aliases: ["alpha"])
        alpha.zone = "home"
        var beta = SSHHost(aliases: ["beta"])
        beta.zone = "home"
        var gamma = SSHHost(aliases: ["gamma"])
        gamma.zone = "work"
        file.append(host: alpha)
        file.append(host: beta)
        file.append(host: gamma)

        for host in file.hosts where host.zone == "home" {
            var updated = host
            updated.zone = "lab"
            file.update(updated)
        }

        #expect(file.hosts.first { $0.aliases.first == "alpha" }?.zone == "lab")
        #expect(file.hosts.first { $0.aliases.first == "beta" }?.zone == "lab")
        #expect(file.hosts.first { $0.aliases.first == "gamma" }?.zone == "work")
        let serialized = file.serialize()
        #expect(serialized.contains("# sshCM-zone: work"))
        #expect(!serialized.contains("# sshCM-zone: home"))
    }
}
