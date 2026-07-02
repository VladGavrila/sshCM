import Foundation

/// A validated, extracted update ready to be swapped in. `signatureVerified` is
/// `false` when the bundle isn't signed by the expected developer; the caller
/// then asks the user to accept the unsigned build before installing.
///
/// Lives here (not on `AppInstaller`) so `UpdateChecker`'s state machine can be
/// unit-tested with a fake installer, without dragging in `AppInstaller`'s
/// `codesign`/`ditto`/`NSApplication` machinery.
struct PreparedInstall: Sendable, Equatable {
    let newApp: URL
    let zipURL: URL
    let signatureVerified: Bool
}

/// The install side of the updater, injected into `UpdateChecker` so the
/// download→verify→install→confirm flow can be exercised without a real signed
/// bundle. `AppInstaller` provides the live implementation (`LiveUpdateInstaller`).
protocol UpdateInstalling: Sendable {
    /// Extract and validate the update without touching the installed app.
    /// Reports signer verification via `PreparedInstall.signatureVerified`
    /// rather than throwing, so the caller can offer an explicit opt-in.
    func verifyAndPrepare(zipURL: URL, expectedBundleID: String) async throws -> PreparedInstall
    /// Swap the (verified or user-accepted) update in for the running app.
    func commitInstall(_ prepared: PreparedInstall) async throws
}

/// Default installer used when none is injected (SwiftUI previews, the SPM test
/// build). The real app always injects `LiveUpdateInstaller`, so this never runs
/// in production — it just keeps `UpdateChecker` constructible without the
/// AppKit-bound installer.
struct DisabledUpdateInstaller: UpdateInstalling {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "Updates are not available in this build." }
    }
    func verifyAndPrepare(zipURL: URL, expectedBundleID: String) async throws -> PreparedInstall {
        throw NotConfigured()
    }
    func commitInstall(_ prepared: PreparedInstall) async throws {
        throw NotConfigured()
    }
}
