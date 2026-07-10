import Foundation
import Testing
@testable import sshCMUtilities

// Temp-dir sandbox helper: every test gets its own directory under
// NSTemporaryDirectory(), cleaned up automatically by the OS.
private func makeSandbox() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConfigLocationTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// MARK: - resolveTarget

@Suite("ConfigLocation – resolveTarget")
struct ResolveTargetTests {
    @Test func plainFileResolvesToItself() throws {
        let dir = makeSandbox()
        let file = dir.appendingPathComponent("config")
        try Data("hi".utf8).write(to: file)
        #expect(try ConfigLocation.resolveTarget(of: file) == file)
    }

    @Test func oneHopSymlinkResolvesToTarget() throws {
        let dir = makeSandbox()
        let target = dir.appendingPathComponent("real")
        try Data("hi".utf8).write(to: target)
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try ConfigLocation.resolveTarget(of: link).path == target.path)
    }

    @Test func chainOfSymlinksResolvesToFinalTarget() throws {
        let dir = makeSandbox()
        let target = dir.appendingPathComponent("real")
        try Data("hi".utf8).write(to: target)
        let mid = dir.appendingPathComponent("mid")
        try FileManager.default.createSymbolicLink(at: mid, withDestinationURL: target)
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: mid)
        #expect(try ConfigLocation.resolveTarget(of: link).path == target.path)
    }

    @Test func relativeSymlinkResolvesAgainstLinkDirectory() throws {
        let dir = makeSandbox()
        let target = dir.appendingPathComponent("real")
        try Data("hi".utf8).write(to: target)
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "real")
        #expect(try ConfigLocation.resolveTarget(of: link).path == target.path)
    }

    @Test func danglingSymlinkStillReturnsTarget() throws {
        let dir = makeSandbox()
        let missingTarget = dir.appendingPathComponent("nope")
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missingTarget)
        #expect(try ConfigLocation.resolveTarget(of: link).path == missingTarget.path)
    }

    @Test func cycleThrows() throws {
        let dir = makeSandbox()
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try FileManager.default.createSymbolicLink(atPath: a.path, withDestinationPath: "b")
        try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: "a")
        #expect(throws: ConfigLocation.LocationError.symlinkCycle) {
            _ = try ConfigLocation.resolveTarget(of: a)
        }
    }
}

// MARK: - planAdoption

@Suite("ConfigLocation – planAdoption")
struct PlanAdoptionTests {
    @Test func targetWithContentAdopts() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        let chosen = dir.appendingPathComponent("synced")
        try Data("Host synced-host\n".utf8).write(to: chosen)

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: chosen)
        guard case .adoptTargetContent(let backupURL) = plan else {
            Issue.record("expected adoptTargetContent")
            return
        }
        #expect(backupURL != nil)
    }

    @Test func missingTargetSeeds() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        let chosen = dir.appendingPathComponent("synced")

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: chosen)
        guard case .seedTargetFromLocal(let backupURL) = plan else {
            Issue.record("expected seedTargetFromLocal")
            return
        }
        #expect(backupURL != nil)
    }

    @Test func emptyTargetSeeds() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        let chosen = dir.appendingPathComponent("synced")
        try Data("   \n".utf8).write(to: chosen)

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: chosen)
        guard case .seedTargetFromLocal = plan else {
            Issue.record("expected seedTargetFromLocal")
            return
        }
    }

    @Test func choosingConfigItselfThrows() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)

        #expect(throws: ConfigLocation.LocationError.targetIsConfig) {
            _ = try ConfigLocation.planAdoption(configURL: config, chosen: config)
        }
    }

    @Test func choosingLinkBackToConfigThrows() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        let link = dir.appendingPathComponent("link-to-config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)

        #expect(throws: ConfigLocation.LocationError.targetIsConfig) {
            _ = try ConfigLocation.planAdoption(configURL: config, chosen: link)
        }
    }

    @Test func symlinkedConfigHasNoBackup() throws {
        let dir = makeSandbox()
        let target = dir.appendingPathComponent("real")
        try Data("Host old\n".utf8).write(to: target)
        let config = dir.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: target)
        let chosen = dir.appendingPathComponent("synced")
        try Data("Host synced-host\n".utf8).write(to: chosen)

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: chosen)
        guard case .adoptTargetContent(let backupURL) = plan else {
            Issue.record("expected adoptTargetContent")
            return
        }
        #expect(backupURL == nil)
    }

    @Test func backupNameCollisionAppendsSuffix() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        let chosen = dir.appendingPathComponent("synced")

        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: fixedNow).replacingOccurrences(of: ":", with: "")
        let existing = dir.appendingPathComponent("config.backup-\(stamp)")
        try Data("taken".utf8).write(to: existing)

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: chosen, now: fixedNow)
        guard case .seedTargetFromLocal(let backupURL) = plan, let backupURL else {
            Issue.record("expected seedTargetFromLocal with backup")
            return
        }
        #expect(backupURL.lastPathComponent == "config.backup-\(stamp)-2")
    }
}

// MARK: - execute

@Suite("ConfigLocation – execute")
struct ExecuteTests {
    @Test func seedModeMovesLocalContentIntoTargetAndLinks() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        let target = dir.appendingPathComponent("synced")

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: target)
        try ConfigLocation.execute(plan, configURL: config, target: target)

        #expect(ConfigLocation.linkedTarget(configURL: config)?.path == target.path)
        let targetData = try Data(contentsOf: target)
        #expect(String(data: targetData, encoding: .utf8) == "Host old\n")

        let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)

        guard case .seedTargetFromLocal(let backupURL) = plan, let backupURL else {
            Issue.record("expected backup URL")
            return
        }
        let backupData = try Data(contentsOf: backupURL)
        #expect(String(data: backupData, encoding: .utf8) == "Host old\n")
    }

    @Test func adoptModeKeepsTargetContentAndBacksUpLocal() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        let target = dir.appendingPathComponent("synced")
        try Data("Host synced-host\n".utf8).write(to: target)

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: target)
        try ConfigLocation.execute(plan, configURL: config, target: target)

        #expect(ConfigLocation.linkedTarget(configURL: config)?.path == target.path)
        let targetData = try Data(contentsOf: target)
        #expect(String(data: targetData, encoding: .utf8) == "Host synced-host\n")

        guard case .adoptTargetContent(let backupURL) = plan, let backupURL else {
            Issue.record("expected backup URL")
            return
        }
        let backupData = try Data(contentsOf: backupURL)
        #expect(String(data: backupData, encoding: .utf8) == "Host old\n")
    }

    @Test func seedModeWithNoLocalConfigCreatesEmptyTargetNotDangling() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        let target = dir.appendingPathComponent("synced")

        let plan = try ConfigLocation.planAdoption(configURL: config, chosen: target)
        try ConfigLocation.execute(plan, configURL: config, target: target)

        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(ConfigLocation.linkedTarget(configURL: config)?.path == target.path)
    }
}

// MARK: - revert

@Suite("ConfigLocation – revert")
struct RevertTests {
    @Test func revertsSymlinkToRegular0600File() throws {
        let dir = makeSandbox()
        let target = dir.appendingPathComponent("synced")
        try Data("Host synced-host\n".utf8).write(to: target)
        let config = dir.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: target)

        try ConfigLocation.revert(configURL: config)

        #expect(ConfigLocation.linkedTarget(configURL: config) == nil)
        let data = try Data(contentsOf: config)
        #expect(String(data: data, encoding: .utf8) == "Host synced-host\n")
        let attrs = try FileManager.default.attributesOfItem(atPath: config.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)

        // Synced file itself is untouched.
        let targetData = try Data(contentsOf: target)
        #expect(String(data: targetData, encoding: .utf8) == "Host synced-host\n")
    }

    @Test func revertingNonSymlinkThrowsNotLinked() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)

        #expect(throws: ConfigLocation.LocationError.notLinked) {
            try ConfigLocation.revert(configURL: config)
        }
    }
}

// MARK: - writeTarget

@Suite("ConfigLocation – writeTarget")
struct WriteTargetTests {
    @Test func plainConfigWritesToItself() throws {
        let dir = makeSandbox()
        let config = dir.appendingPathComponent("config")
        try Data("Host old\n".utf8).write(to: config)
        #expect(try ConfigLocation.writeTarget(for: config).path == config.path)
    }

    @Test func symlinkedConfigWritesToResolvedTarget() throws {
        let dir = makeSandbox()
        let target = dir.appendingPathComponent("synced")
        try Data("Host old\n".utf8).write(to: target)
        let config = dir.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: target)
        #expect(try ConfigLocation.writeTarget(for: config).path == target.path)
    }

    @Test func missingParentDirectoryThrows() throws {
        let dir = makeSandbox()
        let target = dir.appendingPathComponent("missing-mount/synced")
        let config = dir.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: target)

        #expect(throws: ConfigLocation.LocationError.targetUnavailable) {
            _ = try ConfigLocation.writeTarget(for: config)
        }
    }
}
