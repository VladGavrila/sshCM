import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppsSettingsTab()
                .tabItem { Label("Apps", systemImage: "app.badge") }
            TagsSettingsTab()
                .tabItem { Label("Tags", systemImage: "tag") }
            UpdatesSettingsTab()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 460)
        .background(
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onAppear { SettingsWindowGuard.start() }
    }
}

/// Keeps the Settings window floating above the main window and blocks clicks
/// on the main window while Settings is open, restoring both on close.
///
/// Deliberately doesn't touch `NSWindow.delegate`: an earlier version installed
/// a custom `NSWindowDelegate` per window, but that fights with SwiftUI's own
/// internal window delegate (`AppKitWindowController`), which periodically
/// reclaims `window.delegate` for itself. Each reclaim made our global
/// `didBecomeKeyNotification` watcher (needed because switching the Dock/Menu
/// Bar `NSApp.activationPolicy` while Settings is open can otherwise leave it
/// un-floated) think a "new" Settings window had appeared and reinstall,
/// repeatedly calling `makeKeyAndOrderFront` — which raced with in-flight
/// clicks on the embedded segmented control and intermittently dropped them
/// (other controls like tab-switching, with simpler hit-testing, kept working,
/// which is what made this hard to pin down). Tracking everything here with
/// passive global notifications, gated to fire only on the open/close edges
/// rather than every key-status change, avoids that fight entirely.
///
/// Blocking is done with a local event monitor that swallows mouse-downs
/// targeting the main window, rather than `NSWindow.ignoresMouseEvents`:
/// that makes the window click-*through*, so the click lands on whatever is
/// behind it (often another app), stealing focus instead of being blocked.
@MainActor
enum SettingsWindowGuard {
    /// The Settings window's title tracks whichever tab is selected (macOS sets
    /// it from the active `Label`), so this is a precise way to recognize it —
    /// unlike "any non-main, non-palette key window," which also matches
    /// unrelated windows like `NSAlert` panels.
    private static let knownTabTitles: Set<String> = ["General", "Apps", "Tags", "Advanced", "Updates"]

    private static var didStart = false
    private static var isOpen = false
    private static weak var settingsWindow: NSWindow?
    private static var clickMonitor: Any?

    static func start() {
        guard !didStart else { return }
        didStart = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notification in
            guard let window = notification.object as? NSWindow, knownTabTitles.contains(window.title) else { return }
            settingsWindow = window
            guard !isOpen else { return }
            isOpen = true
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            installClickMonitorIfNeeded()
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
            isOpen = false
            settingsWindow = nil
            window.level = .normal
            removeClickMonitor()
        }
    }

    /// Temporarily drops the Settings window to normal level so a sheet/alert
    /// attached to the main window (e.g. the update-check result) isn't left
    /// hidden behind it, then restores floating once that result is dismissed.
    static func setLoweredForResultPresentation(_ lowered: Bool) {
        settingsWindow?.level = lowered ? .normal : .floating
    }

    private static func installClickMonitorIfNeeded() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            guard isOpen, let mainWindow = MainWindowCloseGuard.mainWindow, event.window === mainWindow else {
                return event
            }
            return nil
        }
    }

    private static func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(AppPresentation.storageKey) private var presentationRaw: String = AppPresentation.dock.rawValue
    @AppStorage(KeyShortcut.StorageKey.enabled) private var hotKeyEnabled: Bool = true
    @AppStorage(KeyShortcut.Definition.mainWindow.enabledKey)
    private var mainWindowHotKeyEnabled: Bool = KeyShortcut.Definition.mainWindow.defaultEnabled

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
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
}

// MARK: - Apps

private struct AppsSettingsTab: View {
    @Environment(RemoteAppsStore.self) private var remoteAppsStore

    @AppStorage("defaultTerminalAppPath") private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath
    @AppStorage(TerminalLauncher.keepSessionOpenKey) private var keepSessionOpen: Bool = true

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
                    Text(RemoteAccessApp.screenSharingName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(remoteAppsStore.apps) { app in
                    remoteAppRow(app)
                }
                Button {
                    remoteAppsStore.add(name: "", appPath: "", showsPort: true)
                } label: {
                    Label("Add Remote App", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Remote Apps")
            } footer: {
                Text("Used for each host's \"Remote app\" selection and the \"Connect via VNC\" action. Screen Sharing is always available and can't be reconfigured here — add another entry below if you'd rather use a different app for that role. Turn on \"Show VNC port\" for VNC-protocol apps (TigerVNC, RealVNC, …) so the port field appears when picking them; leave it off for apps that connect by their own ID (TeamViewer, RustDesk, …), which instead launch with just the host's IP. If a chosen app isn't found, sshCM falls back to your system's default vnc:// handler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            remoteAppsStore.pruneIncomplete()
        }
    }

    private var displayName: String {
        let url = URL(fileURLWithPath: terminalAppPath)
        return url.deletingPathExtension().lastPathComponent
    }

    @ViewBuilder
    private func remoteAppRow(_ app: RemoteAccessApp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Name", text: nameBinding(for: app), prompt: Text("App name"))
                    .frame(maxWidth: 160)
                Text(remoteAppDisplayName(app))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose…") { chooseRemoteApp(app) }
                Button(role: .destructive) {
                    remoteAppsStore.remove(id: app.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            Toggle("Show VNC port", isOn: showsPortBinding(for: app))
                .font(.caption)
        }
    }

    private func remoteAppDisplayName(_ app: RemoteAccessApp) -> String {
        guard !app.appPath.isEmpty else { return "No app chosen" }
        return URL(fileURLWithPath: app.appPath).deletingPathExtension().lastPathComponent
    }

    private func nameBinding(for app: RemoteAccessApp) -> Binding<String> {
        Binding(
            get: { app.name },
            set: { var updated = app; updated.name = $0; remoteAppsStore.update(updated) }
        )
    }

    private func showsPortBinding(for app: RemoteAccessApp) -> Binding<Bool> {
        Binding(
            get: { app.showsPort },
            set: { var updated = app; updated.showsPort = $0; remoteAppsStore.update(updated) }
        )
    }

    private func chooseRemoteApp(_ app: RemoteAccessApp) {
        guard let url = chooseApplication(title: "Choose Remote App") else { return }
        var updated = app
        updated.appPath = url.path
        if updated.name.trimmingCharacters(in: .whitespaces).isEmpty {
            updated.name = url.deletingPathExtension().lastPathComponent
        }
        remoteAppsStore.update(updated)
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

// MARK: - Tags

private struct TagsSettingsTab: View {
    @Environment(TagsStore.self) private var tagsStore

    @State private var dropTargetTag: HostTag?
    @State private var draggingTag: HostTag?
    @State private var endDropTargeted: Bool = false

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
    }

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
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @Environment(ConfigStore.self) private var store

    @AppStorage(HostsFilePublisher.defaultsKey) private var publishToHostsFile: Bool = false
    @AppStorage("defaultPublicKeyPath") private var defaultPublicKeyPath: String = ""

    @State private var hostsFileAlert: String?
    @State private var discoveredPublicKeys: [URL] = []

    var body: some View {
        Form {
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
        .onAppear {
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
}

// MARK: - Updates

private struct UpdatesSettingsTab: View {
    @Environment(UpdateChecker.self) private var updater

    @AppStorage("autoCheckForUpdates") private var autoCheck: Bool = true

    var body: some View {
        Form {
            Section {
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
        .onAppear {
            autoCheck = updater.autoCheckForUpdates
        }
        .onChange(of: updater.state) { _, newState in
            // The update result (available/up-to-date/error) renders as a sheet
            // or alert attached to the main window, which would otherwise be
            // hidden behind the always-on-top Settings window.
            SettingsWindowGuard.setLoweredForResultPresentation(hasResultToShow(newState))
        }
        .onDisappear {
            SettingsWindowGuard.setLoweredForResultPresentation(false)
        }
    }

    private func hasResultToShow(_ state: UpdateChecker.State) -> Bool {
        switch state {
        case .upToDate, .available, .error:
            return true
        case .idle, .checking, .downloading, .installing:
            return false
        }
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
}

#Preview {
    SettingsView()
        .environment(ConfigStore())
        .environment(UpdateChecker())
        .environment(TagsStore())
        .environment(RemoteAppsStore())
}
