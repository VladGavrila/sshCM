import SwiftUI

struct UpdateAvailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var checker: UpdateChecker
    let release: UpdateChecker.Release

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Update Available — sshCM \(release.tag)")
                    .font(.title2).bold()
                Text("Current: \(checker.currentVersionString)  →  New: \(release.version.description)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                Group {
                    if release.notes.isEmpty {
                        Text("No release notes provided.")
                            .italic()
                            .foregroundStyle(.secondary)
                    } else {
                        MarkdownView(text: release.notes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 540, height: 440)
    }

    @ViewBuilder
    private var footer: some View {
        switch checker.state {
        case .available:
            HStack {
                Button("Skip This Version") { checker.skip(release); dismiss() }
                Spacer()
                Button("Remind Me Later") { checker.dismissTransient(); dismiss() }
                Button("Install Update") { checker.downloadAndInstall(release) }
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: p)
                HStack {
                    Text("Downloading… \(Int(p * 100))%")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { checker.cancelDownload() }
                }
            }
        case .installing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Installing update… app will relaunch.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        case .confirmUnsigned:
            VStack(alignment: .leading, spacing: 8) {
                Label("Signature verification failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                Text("This update isn't signed by the expected developer. Install it anyway only if you trust the source of this download.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { checker.cancelUnsignedInstall(); dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Install Anyway", role: .destructive) { checker.confirmUnsignedInstall() }
                }
            }
        case .error(let msg):
            VStack(alignment: .leading, spacing: 8) {
                Text(msg).font(.callout).foregroundStyle(.red)
                HStack {
                    Spacer()
                    Button("Close") { checker.dismissTransient(); dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        case .idle, .checking, .upToDate:
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
