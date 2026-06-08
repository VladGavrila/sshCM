import SwiftUI

/// Shown when the user connects to a host whose SSH host key has changed.
/// Replaces the old AppKit `NSAlert` so the warning matches the rest of the
/// app. Two stages: the warning itself (with the four remediation choices), and
/// — after removing the old key — an offer to re-copy the public key, since a
/// changed key most often means the host was rebuilt/re-imaged.
///
/// Purely presentational: the side effects (removing the key, persisting a
/// bypass, launching ssh, seeding) are performed by the closures the caller
/// wires to `HostConnector`.
struct HostKeyWarningSheet: View {
    @Environment(\.dismiss) private var dismiss

    let warning: HostConnector.KeyWarning

    /// Removes the offending `known_hosts` entry and clears the warning.
    let onRemoveKey: () -> Void
    /// Re-copy the public key to the (re-imaged) host.
    let onReseed: () -> Void
    /// Connect normally after removing the old key.
    let onConnect: () -> Void
    /// Connect once with host-key checking disabled.
    let onBypassOnce: () -> Void
    /// Always bypass host-key checking for this host, then connect.
    let onBypassPersist: () -> Void

    private enum Stage {
        case warning
        case reseedOffer
    }

    @State private var stage: Stage = .warning

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            switch stage {
            case .warning:
                warningBody
            case .reseedOffer:
                reseedBody
            }

            Divider()

            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stage == .warning ? "exclamationmark.triangle.fill" : "key.fill")
                .font(.title2)
                .foregroundStyle(stage == .warning ? .orange : .blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(stage == .warning
                     ? "Host key for \(warning.host.title) has changed"
                     : "Re-copy your public key to \(warning.host.title)?")
                    .font(.headline)
                Text(warning.target)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Warning stage

    private var warningBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
            The SSH host key presented by this server no longer matches the one in \
            your known_hosts file. This can happen after a legitimate server rebuild \
            — but it is also exactly what a man-in-the-middle attack looks like.
            """)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("Only proceed if you can verify this new key out-of-band.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                labelledValue("Entry", warning.target)
                labelledValue("New key", warning.fingerprint)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func labelledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Re-seed stage

    private var reseedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("""
            The old key has been removed. A changed host key usually means this \
            server was rebuilt or re-imaged, which also clears its authorized_keys.
            """)
                .fixedSize(horizontal: false, vertical: true)
            Text("Re-copy your public key now so you can keep logging in without a password.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        switch stage {
        case .warning:
            Button("Always Bypass") {
                onBypassPersist()
                dismiss()
            }
            Button("Bypass Once") {
                onBypassOnce()
                dismiss()
            }
            Button("Remove Old Key") {
                onRemoveKey()
                stage = .reseedOffer
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        case .reseedOffer:
            Button("Skip & Connect") {
                onConnect()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Set Up Key…") {
                onReseed()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
