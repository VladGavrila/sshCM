import Foundation
import Testing
@testable import sshCMUtilities

@MainActor
@Suite("UpdateChecker – install/confirm flow")
struct UpdateCheckerTests {

    /// Records what was called and lets a test force verify/commit outcomes,
    /// so the state machine can be exercised without a real signed bundle.
    final class FakeInstaller: UpdateInstalling, @unchecked Sendable {
        var prepared: PreparedInstall?
        var verifyError: Error?
        var commitError: Error?
        private(set) var verifyCount = 0
        private(set) var commitCount = 0

        func verifyAndPrepare(zipURL: URL, expectedBundleID: String) async throws -> PreparedInstall {
            verifyCount += 1
            if let verifyError { throw verifyError }
            return prepared ?? PreparedInstall(newApp: zipURL, zipURL: zipURL, signatureVerified: true)
        }

        func commitInstall(_ prepared: PreparedInstall) async throws {
            commitCount += 1
            if let commitError { throw commitError }
        }
    }

    struct Boom: Error {}

    private let dummyZip = URL(fileURLWithPath: "/tmp/sshCM.zip")

    private func makeRelease() -> UpdateChecker.Release {
        UpdateChecker.Release(
            version: SemanticVersion("1.16.1")!,
            tag: "v1.16.1",
            notes: "notes",
            downloadURL: URL(string: "https://example.com/sshCM.zip")!,
            assetSize: 123
        )
    }

    private func prepared(signatureVerified: Bool) -> PreparedInstall {
        PreparedInstall(newApp: dummyZip, zipURL: dummyZip, signatureVerified: signatureVerified)
    }

    @Test func verifiedUpdateInstallsWithoutPrompting() async {
        let fake = FakeInstaller()
        fake.prepared = prepared(signatureVerified: true)
        let checker = UpdateChecker(installer: fake)

        await checker.installDownloaded(dummyZip, release: makeRelease())

        #expect(fake.commitCount == 1)
        if case .confirmUnsigned = checker.state { Issue.record("must not prompt for a verified build") }
    }

    @Test func unsignedUpdatePromptsInsteadOfInstalling() async {
        let fake = FakeInstaller()
        fake.prepared = prepared(signatureVerified: false)
        let checker = UpdateChecker(installer: fake)
        let release = makeRelease()

        await checker.installDownloaded(dummyZip, release: release)

        #expect(fake.commitCount == 0)                       // did NOT silently install
        #expect(checker.state == .confirmUnsigned(release))  // waiting on the user
    }

    @Test func acceptingUnsignedRunsCommit() async {
        let fake = FakeInstaller()
        fake.prepared = prepared(signatureVerified: false)
        let checker = UpdateChecker(installer: fake)

        await checker.installDownloaded(dummyZip, release: makeRelease())
        await checker.commitPendingUnsigned()

        #expect(fake.commitCount == 1)
        #expect(checker.state == .installing)
    }

    @Test func cancelingUnsignedResetsAndNeverCommits() async {
        let fake = FakeInstaller()
        fake.prepared = prepared(signatureVerified: false)
        let checker = UpdateChecker(installer: fake)

        await checker.installDownloaded(dummyZip, release: makeRelease())
        checker.cancelUnsignedInstall()
        #expect(checker.state == .idle)

        // A confirm attempt after cancel must be a no-op — the pending install is gone.
        await checker.commitPendingUnsigned()
        #expect(fake.commitCount == 0)
    }

    @Test func verifyFailureSurfacesError() async {
        let fake = FakeInstaller()
        fake.verifyError = Boom()
        let checker = UpdateChecker(installer: fake)

        await checker.installDownloaded(dummyZip, release: makeRelease())

        if case .error = checker.state {} else { Issue.record("expected .error, got \(checker.state)") }
    }

    @Test func commitFailureSurfacesError() async {
        let fake = FakeInstaller()
        fake.prepared = prepared(signatureVerified: true)
        fake.commitError = Boom()
        let checker = UpdateChecker(installer: fake)

        await checker.installDownloaded(dummyZip, release: makeRelease())

        if case .error = checker.state {} else { Issue.record("expected .error, got \(checker.state)") }
    }

    @Test func disabledInstallerRefusesToInstall() async {
        // Guards the constructibility fallback: a UpdateChecker() with no
        // installer injected must never silently succeed at installing.
        let checker = UpdateChecker()

        await checker.installDownloaded(dummyZip, release: makeRelease())

        if case .error = checker.state {} else { Issue.record("expected .error, got \(checker.state)") }
    }
}
