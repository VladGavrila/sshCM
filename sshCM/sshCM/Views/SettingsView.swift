import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(UpdateChecker.self) private var updater
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ConfigStore.self) private var store

    @AppStorage("defaultTerminalAppPath") private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath
    @AppStorage(TerminalLauncher.keepSessionOpenKey) private var keepSessionOpen: Bool = true
    @AppStorage(AppStorageKey.defaultMacOSVNCAppPath.rawValue) private var macOSVNCAppPath: String = VNCLauncher.defaultMacOSVNCAppPath
    @AppStorage(AppStorageKey.defaultLinuxVNCAppPath.rawValue) private var linuxVNCAppPath: String = ""
    @AppStorage("defaultPublicKeyPath") private var defaultPublicKeyPath: String = ""
    @AppStorage("autoCheckForUpdates") private var autoCheck: Bool = true
    @AppStorage(KeyShortcut.StorageKey.enabled) private var hotKeyEnabled: Bool = true
    @AppStorage(KeyShortcut.Definition.mainWindow.enabledKey)
    private var mainWindowHotKeyEnabled: Bool = KeyShortcut.Definition.mainWindow.defaultEnabled
    @AppStorage(AppPresentation.storageKey) private var presentationRaw: String = AppPresentation.dock.rawValue
    @AppStorage(HostsFilePublisher.defaultsKey) private var publishToHostsFile: Bool = false

    @State private var dropTargetTag: HostTag?
    @State private var draggingTag: HostTag?
    @State private var discoveredPublicKeys: [URL] = []
    @State private var hostsFileAlert: String?

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

                Toggle("Keep terminal open after session ends", isOn: $keepSessionOpen)
                Text("Stays in an interactive shell when ssh exits (logout or connection reset) so you can review the session. Turn off to close the tab automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(macOSVNCDisplayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…", action: chooseMacOSVNCApp)
                    Button("Reset") {
                        macOSVNCAppPath = VNCLauncher.defaultMacOSVNCAppPath
                    }
                }
                HStack {
                    Text(linuxVNCDisplayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…", action: chooseLinuxVNCApp)
                    Button("Reset") {
                        linuxVNCAppPath = ""
                    }
                }
            } header: {
                Text("VNC")
            } footer: {
                Text("Used for the \"Connect via VNC\" action. macOS hosts open with the app above by default (Screen Sharing); Linux hosts open with the app you choose here (e.g. TigerVNC). If a chosen app isn't found, sshCM falls back to your system's default vnc:// handler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if discoveredPublicKeys.isEmpty {
                    Text("No public keys found in ~/.ssh.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Default public key", selection: $defaultPublicKeyPath) {
                        Text("Auto (first match)").tag("")
                        ForEach(discoveredPublicKeys, id: \.path) { url in
                            Text(url.lastPathComponent).tag(url.path)
                        }
                    }
                }
            } header: {
                Text("Public Key for Setup")
            } footer: {
                Text("Pre-selected when seeding a key into a host's authorized_keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Array(tagsStore.tagOrder.enumerated()), id: \.element) { index, tag in
                    tagOrderRow(tag: tag, isLast: index == tagsStore.tagOrder.count - 1)
                }
                endDropZone
                HStack {
                    Spacer()
                    Button("Reset to Default") {
                        tagsStore.resetOrder()
                    }
                }
            } header: {
                Text("Host Tag Sort Order")
            } footer: {
                Text("Drag the rows to reorder. Host cards are grouped by tag color in this order. Favorites always appear first; untagged hosts last.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Show sshCM as", selection: $presentationRaw) {
                    ForEach(AppPresentation.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: presentationRaw) { _, newValue in
                    let presentation = AppPresentation(rawValue: newValue) ?? .dock
                    NSApp.setActivationPolicy(presentation.activationPolicy)
                    MenuBarStatusItem.shared.apply(presentation)
                    if presentation == .dock {
                        forceMenuBarRefresh()
                    }
                }
            } header: {
                Text("App Presentation")
            } footer: {
                Text("Menu bar mode hides the Dock icon and shows a status item in the menu bar. The app's menu bar (File/Edit/View) is hidden in this mode; use the status item or the global hotkey to access actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Make aliases resolvable system-wide", isOn: $publishToHostsFile)
                    .onChange(of: publishToHostsFile) { _, enabled in
                        Task { await applyHostsFileToggle(enabled) }
                    }
            } header: {
                Text("System-Wide Name Resolution")
            } footer: {
                Text("SSH host aliases normally work only inside ssh. Enable this to also write them into /etc/hosts so other apps — Screen Sharing, VNC, browsers — can reach a host by its alias. Only hosts whose HostName is a literal IP address are published. Because /etc/hosts is a protected system file, macOS asks for an administrator password whenever the published list changes. sshCM keeps the list in sync as you add, edit, and remove hosts, and removes its entries when you turn this off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Command Palette hotkey", isOn: $hotKeyEnabled)
                LabeledContent("Open Command Palette") {
                    ShortcutRecorderView(definition: .palette)
                }
                Toggle("Enable Show Main Window hotkey", isOn: $mainWindowHotKeyEnabled)
                LabeledContent("Show Main Window") {
                    ShortcutRecorderView(definition: .mainWindow)
                }
            } header: {
                Text("Global Hotkeys")
            } footer: {
                Text("System-wide shortcuts that work while sshCM is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .alert(
            "Could not update /etc/hosts",
            isPresented: Binding(
                get: { hostsFileAlert != nil },
                set: { if !$0 { hostsFileAlert = nil } }
            ),
            presenting: hostsFileAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .frame(width: 520, height: 720)
        .background(
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onAppear {
            autoCheck = updater.autoCheckForUpdates
            discoveredPublicKeys = PublicKeyDiscovery.discover()
            if !defaultPublicKeyPath.isEmpty,
               !discoveredPublicKeys.contains(where: { $0.path == defaultPublicKeyPath }) {
                defaultPublicKeyPath = ""
            }
        }
    }

    /// Applies the managed block right after the toggle flips. If the user
    /// cancels the admin prompt or the write fails, revert the toggle so it
    /// reflects what's actually in /etc/hosts.
    private func applyHostsFileToggle(_ enabled: Bool) async {
        let result = enabled
            ? await HostsFilePublisher.sync(hosts: store.file.hosts)
            : await HostsFilePublisher.clear()
        switch result {
        case .unchanged, .updated:
            break
        case .cancelled:
            publishToHostsFile = !enabled
        case .failed(let message):
            publishToHostsFile = !enabled
            hostsFileAlert = message
        }
    }

    @State private var endDropTargeted: Bool = false

    private func nameBinding(for tag: HostTag) -> Binding<String> {
        Binding(
            get: { tagsStore.customName(for: tag) ?? "" },
            set: { tagsStore.rename(tag: tag, to: $0) }
        )
    }

    private var endDropZone: some View {
        Rectangle()
            .fill(endDropTargeted ? Color.accentColor.opacity(0.25) : Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .dropDestination(for: HostTag.self) { items, _ in
                endDropTargeted = false
                draggingTag = nil
                guard let source = items.first else { return false }
                tagsStore.moveToEnd(tag: source)
                return true
            } isTargeted: { value in
                endDropTargeted = value
            }
    }

    @ViewBuilder
    private func tagOrderRow(tag: HostTag, isLast: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder")
            Circle()
                .fill(tag.color)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .help(tag.displayName)
            TextField(
                tag.displayName,
                text: nameBinding(for: tag),
                prompt: Text(tag.displayName)
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .opacity(draggingTag == tag ? 0.4 : 1.0)
        .overlay(alignment: .top) {
            if dropTargetTag == tag {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .draggable(tag) {
            HStack(spacing: 6) {
                Circle().fill(tag.color).frame(width: 14, height: 14)
                Text(tag.displayName).font(.callout)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .onAppear { draggingTag = tag }
            .onDisappear { draggingTag = nil }
        }
        .dropDestination(for: HostTag.self) { items, _ in
            dropTargetTag = nil
            draggingTag = nil
            guard let source = items.first else { return false }
            tagsStore.move(tag: source, before: tag)
            return true
        } isTargeted: { isTargeted in
            dropTargetTag = isTargeted ? tag : (dropTargetTag == tag ? nil : dropTargetTag)
        }
    }

    private var displayName: String {
        let url = URL(fileURLWithPath: terminalAppPath)
        return url.deletingPathExtension().lastPathComponent
    }

    private var macOSVNCDisplayName: String {
        URL(fileURLWithPath: macOSVNCAppPath).deletingPathExtension().lastPathComponent
    }

    private var linuxVNCDisplayName: String {
        guard !linuxVNCAppPath.isEmpty else { return "System default (vnc:// handler)" }
        return URL(fileURLWithPath: linuxVNCAppPath).deletingPathExtension().lastPathComponent
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

    private func forceMenuBarRefresh() {
        // .accessory → .regular leaves the menu bar empty until another app takes
        // focus. Briefly activate another running app, then come back, to force
        // AppKit to rebuild our menu bar.
        let other = NSWorkspace.shared.runningApplications.first { app in
            app.activationPolicy == .regular
                && app.processIdentifier != NSRunningApplication.current.processIdentifier
                && !app.isTerminated
                && !app.isHidden
        }
        if let other {
            other.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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

    private func chooseMacOSVNCApp() {
        guard let url = chooseApplication(title: "Choose macOS VNC Application") else { return }
        macOSVNCAppPath = url.path
    }

    private func chooseLinuxVNCApp() {
        guard let url = chooseApplication(title: "Choose Linux VNC Application") else { return }
        linuxVNCAppPath = url.path
    }

    private func chooseApplication(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url : nil
    }
}

#Preview {
    SettingsView()
        .environment(ConfigStore())
        .environment(UpdateChecker())
        .environment(TagsStore())
}
