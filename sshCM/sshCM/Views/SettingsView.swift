import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("defaultTerminalAppPath") private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath

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
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 200)
    }

    private var displayName: String {
        let url = URL(fileURLWithPath: terminalAppPath)
        return url.deletingPathExtension().lastPathComponent
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
}
