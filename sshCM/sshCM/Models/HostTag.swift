import Foundation

/// The 7-color per-host tag. UI-only metadata (not an SSH concept), stored on
/// the host as a `# sshCM-tag:` marker — see `SSHConfigParser.tagMarker`.
///
/// This core type is Foundation-only so it can live in the pure model layer
/// (and be referenced by `SSHHost`); the SwiftUI-bound pieces (`color`,
/// `Transferable`) are added in `HostTag+SwiftUI.swift` in the app target.
enum HostTag: String, CaseIterable, Identifiable, Codable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    static var defaultOrder: [HostTag] {
        [.green, .yellow, .orange, .red, .blue, .purple, .gray]
    }
}
