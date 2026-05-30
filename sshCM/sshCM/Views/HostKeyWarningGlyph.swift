import SwiftUI

/// Yellow warning shown next to a host whose SSH host key no longer matches
/// `known_hosts`. Rendered only when the second-pass key check reports
/// `.changed`; connecting to such a host opens the remediation dialog.
struct HostKeyWarningGlyph: View {
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: size))
            .foregroundStyle(.yellow)
            .help("Host key changed since it was last recorded — connect to review")
            .accessibilityLabel("Host key changed")
    }
}
