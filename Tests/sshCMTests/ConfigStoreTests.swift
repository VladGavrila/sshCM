import Foundation
import Testing
@testable import sshCMModels

// ConfigStore is a @MainActor class that imports AppKit/Observation and lives in
// the Xcode target, not the sshCMModels SPM target.  These tests exercise the
// pure model layer it delegates to (SSHConfigFile / SSHConfigParser) via a
// temporary file, validating the URL-injection mechanism.

@Suite("ConfigStore – URL injection contract (via model layer)")
struct ConfigStoreTests {

    // Helpers that replicate ConfigStore's load/persist logic so we can test
    // round-trip behaviour without the @MainActor class itself.
    private func writeConfig(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)!.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func readAndParse(from url: URL) -> SSHConfigFile {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return SSHConfigFile() }
        return SSHConfigParser.parse(text)
    }

    @Test func temporaryFileRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshcm-test-\(UUID()).config")
        defer { try? FileManager.default.removeItem(at: url) }

        let text = "Host testhost\n    HostName test.example.com\n    User admin\n"
        try writeConfig(text, to: url)

        let file = readAndParse(from: url)
        #expect(file.hosts.count == 1)
        #expect(file.hosts[0].aliases.first == "testhost")
        #expect(file.hosts[0].hostName == "test.example.com")
        #expect(file.hosts[0].user == "admin")
    }

    @Test func addAndPersistRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshcm-test-\(UUID()).config")
        defer { try? FileManager.default.removeItem(at: url) }

        var file = SSHConfigFile()
        file.append(host: SSHHost(aliases: ["newhost"], hostName: "new.example.com", user: "root"))
        try writeConfig(file.serialize(), to: url)

        let reloaded = readAndParse(from: url)
        #expect(reloaded.hosts.count == 1)
        #expect(reloaded.hosts[0].aliases.first == "newhost")
        #expect(reloaded.hosts[0].user == "root")
    }

    @Test func removeAndPersistRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshcm-test-\(UUID()).config")
        defer { try? FileManager.default.removeItem(at: url) }

        let text = "Host alpha\n    HostName a.com\nHost beta\n    HostName b.com\n"
        try writeConfig(text, to: url)

        var file = readAndParse(from: url)
        let betaID = file.hosts.first { $0.aliases.first == "beta" }!.id
        file.remove(id: betaID)
        try writeConfig(file.serialize(), to: url)

        let reloaded = readAndParse(from: url)
        #expect(reloaded.hosts.count == 1)
        #expect(reloaded.hosts[0].aliases.first == "alpha")
    }
}
