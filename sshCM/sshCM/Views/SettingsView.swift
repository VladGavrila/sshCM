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
            ZonesSettingsTab()
                .tabItem { Label("Zones", systemImage: "network") }
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
    private static let knownTabTitles: Set<String> = ["General", "Apps", "Tags", "Zones", "Advanced", "Updates"]

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
                .help(tagsStore.displayName(for: tag))
            TextField(
                tag.rawValue,
                text: nameBinding(for: tag),
                prompt: Text(tag.rawValue)
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
            // The color word is what's actually written to ~/.ssh/config (see
            // SSHConfigParser.tagMarker) — stable across renames and portable
            // across machines, unlike the freeform name above. Only shown once
            // a custom name diverges from it; otherwise the two are identical
            // and the caption would just be noise.
            if tagsStore.customName(for: tag) != nil {
                Text("config: \(tag.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                Text(tagsStore.displayName(for: tag)).font(.callout)
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

// MARK: - Zones

private struct ZonesSettingsTab: View {
    @Environment(ZonesStore.self) private var zonesStore
    @Environment(ConfigStore.self) private var store

    @AppStorage(AppStorageKey.selectedZone.rawValue) private var selectedZone: String = ""

    @State private var newZoneName = ""
    @State private var newZoneRejectionNotice: String?
    @State private var suppressNewZoneFilter = false
    @State private var dropTargetZone: String?
    @State private var endDropTargeted = false
    @State private var zonePendingDeletion: String?
    @State private var assigningZone: String?

    private static let zoneRejectionMessage =
        "Spaces and special characters aren't allowed — use letters, digits, - . or _."

    var body: some View {
        Form {
            Section {
                ForEach(zonesStore.zones, id: \.self) { zone in
                    zoneRow(zone)
                }
                endDropZone
                addZoneRow
            } header: {
                Text("Zones")
            } footer: {
                Text("Group hosts by physical network — home, work, aws. Zones can filter the host list and scope reachability checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(
            get: { assigningZone != nil },
            set: { if !$0 { assigningZone = nil } }
        )) {
            if let zone = assigningZone {
                ZoneAssignSheet(zone: zone, hosts: store.file.hosts)
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { zonePendingDeletion != nil },
                set: { if !$0 { zonePendingDeletion = nil } }
            ),
            presenting: zonePendingDeletion
        ) { zone in
            Button("Remove \"\(zone)\"", role: .destructive) {
                deleteZone(zone)
            }
            Button("Cancel", role: .cancel) {
                zonePendingDeletion = nil
            }
        } message: { zone in
            let count = memberCount(of: zone)
            if count > 0 {
                Text("\(count) host\(count == 1 ? "" : "s") will lose their zone assignment. ~/.ssh/config will be updated.")
            } else {
                Text("This zone has no members.")
            }
        }
    }

    private var deletionTitle: String {
        guard let zone = zonePendingDeletion else { return "" }
        return "Remove zone \"\(zone)\"?"
    }

    private func memberCount(of zone: String) -> Int {
        store.file.hosts.filter { $0.zone == zone }.count
    }

    @ViewBuilder
    private var addZoneRow: some View {
        HStack {
            TextField("Zone name", text: $newZoneName, prompt: Text("Zone name"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: newZoneName) { _, newValue in
                    if suppressNewZoneFilter {
                        suppressNewZoneFilter = false
                        return
                    }
                    let sanitized = ZoneCatalog.sanitizeInput(newValue)
                    if sanitized != newValue {
                        suppressNewZoneFilter = true
                        newZoneName = sanitized
                        newZoneRejectionNotice = Self.zoneRejectionMessage
                    } else {
                        newZoneRejectionNotice = nil
                    }
                }
                .onSubmit(addZone)
            Button("Add Zone", action: addZone)
                .disabled(!canAddZone)
        }
        if let notice = newZoneRejectionNotice {
            Text(notice)
                .font(.caption)
                .foregroundStyle(.red)
        } else if !newZoneName.isEmpty && !canAddZone {
            Text("A zone with this name already exists.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var canAddZone: Bool {
        guard let normalized = ZoneCatalog.normalized(newZoneName) else { return false }
        return !ZoneCatalog.isDuplicate(normalized, in: zonesStore.zones)
    }

    private func addZone() {
        guard canAddZone else { return }
        zonesStore.add(newZoneName)
        newZoneName = ""
        newZoneRejectionNotice = nil
    }

    private func deleteZone(_ zone: String) {
        store.updateAll { host in
            if host.zone == zone { host.zone = nil }
        }
        zonesStore.remove(zone)
        if selectedZone == zone {
            selectedZone = ""
        }
        zonePendingDeletion = nil
    }

    private func rename(_ zone: String, to newName: String) {
        guard let normalized = ZoneCatalog.normalized(newName), normalized != zone else { return }
        guard !ZoneCatalog.isDuplicate(normalized, in: zonesStore.zones) else { return }
        zonesStore.rename(zone, to: normalized)
        store.updateAll { host in
            if host.zone == zone { host.zone = normalized }
        }
        if selectedZone == zone {
            selectedZone = normalized
        }
    }

    private var endDropZone: some View {
        Rectangle()
            .fill(endDropTargeted ? Color.accentColor.opacity(0.25) : Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                endDropTargeted = false
                guard let source = items.first else { return false }
                zonesStore.moveToEnd(zone: source)
                return true
            } isTargeted: { value in
                endDropTargeted = value
            }
    }

    @ViewBuilder
    private func zoneRow(_ zone: String) -> some View {
        ZoneRow(
            zone: zone,
            memberCount: memberCount(of: zone),
            isDropTarget: dropTargetZone == zone,
            onCommitRename: { rename(zone, to: $0) },
            onAssign: { assigningZone = zone },
            onDelete: {
                if memberCount(of: zone) > 0 {
                    zonePendingDeletion = zone
                } else {
                    deleteZone(zone)
                }
            }
        )
        .draggable(zone) {
            Text(zone)
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { items, _ in
            dropTargetZone = nil
            guard let source = items.first else { return false }
            zonesStore.move(zone: source, before: zone)
            return true
        } isTargeted: { isTargeted in
            dropTargetZone = isTargeted ? zone : (dropTargetZone == zone ? nil : dropTargetZone)
        }
    }
}

/// A single zone's settings row. Rename commits on submit/focus-loss rather
/// than per keystroke — unlike tag renames (UserDefaults-only), a zone rename
/// rewrites every member host's marker line in `~/.ssh/config`, so a live
/// per-character binding would hammer the file on every keystroke.
private struct ZoneRow: View {
    let zone: String
    let memberCount: Int
    let isDropTarget: Bool
    let onCommitRename: (String) -> Void
    let onAssign: () -> Void
    let onDelete: () -> Void

    @State private var draft: String = ""
    @State private var suppressDraftFilter = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder")
            TextField("Zone name", text: $draft, prompt: Text("Zone name"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .focused($isFocused)
                .onChange(of: draft) { _, newValue in
                    if suppressDraftFilter {
                        suppressDraftFilter = false
                        return
                    }
                    let sanitized = ZoneCatalog.sanitizeInput(newValue)
                    if sanitized != newValue {
                        suppressDraftFilter = true
                        draft = sanitized
                    }
                }
                .onSubmit { commit() }
                .onChange(of: isFocused) { wasFocused, nowFocused in
                    if wasFocused && !nowFocused { commit() }
                }
            Button {
                onAssign()
            } label: {
                Text(memberCount == 1 ? "Assign Hosts… (1 host)" : "Assign Hosts… (\(memberCount) hosts)")
            }
            Spacer(minLength: 4)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .onAppear { draft = zone }
        .onChange(of: zone) { _, newValue in draft = newValue }
    }

    private func commit() {
        guard draft != zone else { return }
        let normalized = ZoneCatalog.normalized(draft)
        guard let normalized else {
            draft = zone
            return
        }
        onCommitRename(normalized)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @Environment(ConfigStore.self) private var store

    @AppStorage(HostsFilePublisher.defaultsKey) private var publishToHostsFile: Bool = false
    @AppStorage("defaultPublicKeyPath") private var defaultPublicKeyPath: String = ""

    @State private var hostsFileAlert: String?
    @State private var discoveredPublicKeys: [URL] = []

    @State private var linkedTarget: URL?
    @State private var pendingSyncPlan: ConfigLocation.AdoptionPlan?
    @State private var pendingSyncTarget: URL?
    @State private var showAdoptConfirm = false
    @State private var showSeedConfirm = false
    @State private var showRevertConfirm = false
    @State private var configLocationAlert: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    Text(linkedTarget.map(displayPath) ?? "Standard (~/.ssh/config)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Choose Synced File…") { chooseSyncTarget() }
                    if linkedTarget != nil {
                        Button("Revert to Standard…") { showRevertConfirm = true }
                    }
                }
            } header: {
                Text("Config File Location")
            } footer: {
                Text("Point sshCM at a file inside a synced folder (iCloud Drive, Dropbox, Syncthing, …) and ~/.ssh/config becomes a symlink to it — ssh, sshCM, and every other machine read and write the same file, and the sync service moves the bytes. Your current config is backed up before switching. Changes made on another machine are picked up automatically.")
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
        .alert(
            "Couldn't Change Config Location",
            isPresented: Binding(
                get: { configLocationAlert != nil },
                set: { if !$0 { configLocationAlert = nil } }
            ),
            presenting: configLocationAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            "Use the Synced File's Contents?",
            isPresented: $showAdoptConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue") { commitSyncTarget() }
            Button("Cancel", role: .cancel) { cancelPendingSync() }
        } message: {
            Text(adoptConfirmMessage())
        }
        .confirmationDialog(
            "Move Your Config Into the Synced File?",
            isPresented: $showSeedConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue") { commitSyncTarget() }
            Button("Cancel", role: .cancel) { cancelPendingSync() }
        } message: {
            Text(seedConfirmMessage())
        }
        .confirmationDialog(
            "Revert to a Standard Config File?",
            isPresented: $showRevertConfirm,
            titleVisibility: .visible
        ) {
            Button("Revert", role: .destructive) { revertSyncTarget() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("~/.ssh/config will become a regular file again, containing a copy of the synced content. The synced file itself is left untouched.")
        }
        .onAppear {
            discoveredPublicKeys = PublicKeyDiscovery.discover()
            if !defaultPublicKeyPath.isEmpty,
               !discoveredPublicKeys.contains(where: { $0.path == defaultPublicKeyPath }) {
                defaultPublicKeyPath = ""
            }
            refreshLinkedTarget()
        }
    }

    private func refreshLinkedTarget() {
        linkedTarget = ConfigLocation.linkedTarget(configURL: store.configURL)
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private func chooseSyncTarget() {
        guard let chosen = FilePicker.pickConfigSyncTarget() else { return }
        do {
            let plan = try ConfigLocation.planAdoption(configURL: store.configURL, chosen: chosen)
            pendingSyncPlan = plan
            pendingSyncTarget = chosen
            switch plan {
            case .adoptTargetContent:
                showAdoptConfirm = true
            case .seedTargetFromLocal:
                showSeedConfirm = true
            }
        } catch {
            configLocationAlert = error.localizedDescription
        }
    }

    private func adoptConfirmMessage() -> String {
        guard case .adoptTargetContent(let backupURL) = pendingSyncPlan else { return "" }
        if let backupURL {
            return "The synced file's contents will be used. Your current config will be backed up to \(backupURL.lastPathComponent)."
        }
        return "The synced file's contents will be used."
    }

    private func seedConfirmMessage() -> String {
        guard case .seedTargetFromLocal(let backupURL) = pendingSyncPlan else { return "" }
        if let backupURL {
            return "Your current config will be moved into the synced file, and backed up to \(backupURL.lastPathComponent)."
        }
        return "Your current config will be moved into the synced file."
    }

    private func commitSyncTarget() {
        guard let plan = pendingSyncPlan, let target = pendingSyncTarget else { return }
        defer {
            pendingSyncPlan = nil
            pendingSyncTarget = nil
        }
        do {
            try ConfigLocation.execute(plan, configURL: store.configURL, target: target)
            store.configLocationDidChange()
            refreshLinkedTarget()
        } catch {
            configLocationAlert = error.localizedDescription
        }
    }

    private func cancelPendingSync() {
        pendingSyncPlan = nil
        pendingSyncTarget = nil
    }

    private func revertSyncTarget() {
        do {
            try ConfigLocation.revert(configURL: store.configURL)
            store.configLocationDidChange()
            refreshLinkedTarget()
        } catch {
            configLocationAlert = error.localizedDescription
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
        case .idle, .checking, .downloading, .installing, .confirmUnsigned:
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
