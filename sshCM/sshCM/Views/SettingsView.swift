import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(UpdateChecker.self) private var updater

    @AppStorage("defaultTerminalAppPath") private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath
    @AppStorage("autoCheckForUpdates") private var autoCheck: Bool = true

    var body: some View {
        Form {
            Section("Default Terminal Application") {
                HStack {
                    Text(displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…", action: chooseTerminalApp)
                    Button("Reset") {
                        terminalAppPath = TerminalLauncher.defaultTerminalAppPath
                    }
                }
                Text(terminalAppPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $autoCheck)
                    .onChange(of: autoCheck) { _, newValue in
                        updater.autoCheckForUpdates = newValue
                    }
                LabeledContent("Current version", value: updater.currentVersionString)
                LabeledContent("Last checked", value: lastCheckedDescription)
                HStack {
                    Spacer()
                    Button(checkButtonTitle) {
                        Task { await updater.check(userInitiated: true) }
                    }
                    .disabled(isChecking)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .onAppear {
            autoCheck = updater.autoCheckForUpdates
        }
    }

    private var displayName: String {
        let url = URL(fileURLWithPath: terminalAppPath)
        return url.deletingPathExtension().lastPathComponent
    }

    private var lastCheckedDescription: String {
        guard let date = updater.lastCheck else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var isChecking: Bool {
        if case .checking = updater.state { return true }
        if case .downloading = updater.state { return true }
        if case .installing = updater.state { return true }
        return false
    }

    private var checkButtonTitle: String {
        isChecking ? "Checking…" : "Check for Updates Now"
    }

    private func chooseTerminalApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Terminal Application"
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            terminalAppPath = url.path
        }
    }
}

#Preview {
    SettingsView()
        .environment(UpdateChecker())
}
