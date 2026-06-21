// swift-tools-version: 6.0
// Compiles the pure Foundation-only model and utility types into a library target
// so they can be covered by Swift Testing tests without the full Xcode app target.
// Run with: swift test   (from the repo root)
import PackageDescription

let package = Package(
    name: "sshCMCore",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "sshCMModels",
            path: "sshCM/sshCM/Models",
            sources: [
                "AppStorageKey.swift",
                "SSHHost.swift",
                "SSHConfigFile.swift",
                "SSHConfigParser.swift",
                "PortForward.swift",
                "HostListFilter.swift",
                "HostSearchScorer.swift",
                "HostsFileBlock.swift"
            ]
        ),
        .target(
            name: "sshCMUtilities",
            path: "sshCM/sshCM/Utilities",
            sources: ["SemanticVersion.swift"]
        ),
        .testTarget(
            name: "sshCMTests",
            dependencies: ["sshCMModels", "sshCMUtilities"],
            path: "Tests/sshCMTests"
        ),
    ]
)
