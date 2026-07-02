import SwiftUI
import AppKit

enum HostsViewMode: String {
    case card, list
}

struct SeedRequest: Identifiable {
    let id = UUID()
    let host: SSHHost
    let userOverride: String?
}

/// Wraps a decoded import document so it can drive a `.sheet(item:)`.
struct ImportSession: Identifiable {
    let id = UUID()
    let document: HostExportDocument
}

struct ContentView: View {
    @Environment(ConfigStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ReachabilityCache.self) private var reachCache
    @Environment(HostKeyBypassStore.self) private var bypassStore
    @Environment(UpdateChecker.self) private var updater
    @Environment(PaletteBridge.self) private var paletteBridge
    @Environment(RemoteAppsStore.self) private var remoteAppsStore

    @AppStorage(AppStorageKey.defaultTerminalAppPath.rawValue) private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath
    @AppStorage(AppStorageKey.defaultMacOSVNCAppPath.rawValue) private var macOSVNCAppPath: String = VNCLauncher.defaultMacOSVNCAppPath

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var showingAdd = false
    @State private var hostBeingEdited: SSHHost?
    @State private var hostPendingDeletion: SSHHost?
    @State private var currentSeedRequest: SeedRequest?
    @State private var pendingSeedRequests: [SeedRequest] = []
    @State private var searchText: String = ""
    @State private var connectError: String?
    @State private var hostKeyWarning: HostConnector.KeyWarning?
    /// Stashed when the user removes a changed key and opts to re-seed; the seed
    /// sheet is presented from the warning sheet's `onDismiss` so the two sheets
    /// don't fight over presentation.
    @State private var seedAfterWarningDismiss: SeedRequest?
    @State private var presentedRelease: UpdateChecker.Release?
    @State private var typeAheadMonitor: Any?
    @AppStorage(AppStorageKey.hostsViewMode.rawValue) private var viewModeRaw: String = HostsViewMode.card.rawValue
    @AppStorage(AppStorageKey.showOnlyReachable.rawValue) private var showOnlyReachable: Bool = false
    @State private var showingExport = false
    @State private var importSession: ImportSession?
    @State private var importError: String?

    private var viewMode: HostsViewMode {
        HostsViewMode(rawValue: viewModeRaw) ?? .card
    }

    var body: some View {
        baseView
            .sheet(isPresented: $showingAdd) {
                AddHostSheet(onSaved: { host, isNew, added in
                    Task { await considerKeySeeds(host: host, isNew: isNew, addedAlternateUsers: added) }
                })
                .environment(store)
                .environment(tagsStore)
            }
            .sheet(item: $currentSeedRequest, onDismiss: dequeueNextSeed) { request in
                SeedKeySheet(host: request.host, userOverride: request.userOverride)
            }
            .sheet(isPresented: $showingExport) {
                ExportHostsSheet(hosts: store.file.hosts)
                    .environment(tagsStore)
                    .environment(favorites)
                    .environment(reachCache)
            }
            .sheet(item: $importSession) { session in
                ImportHostsSheet(document: session.document)
                    .environment(store)
                    .environment(tagsStore)
                    .environment(favorites)
                    .environment(reachCache)
            }
            .alert(
                "Import Failed",
                isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }),
                presenting: importError
            ) { _ in
                Button("OK") { importError = nil }
            } message: { msg in
                Text(msg)
            }
            .sheet(item: $hostBeingEdited) { (host: SSHHost) in
                AddHostSheet(editing: host, onSaved: { saved, isNew, added in
                    Task { await considerKeySeeds(host: saved, isNew: isNew, addedAlternateUsers: added) }
                })
                    .environment(store)
                    .environment(tagsStore)
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: deletionBinding,
                presenting: hostPendingDeletion
            ) { host in
                Button("Remove \"\(host.title)\"", role: .destructive) {
                    if let alias = host.aliases.first {
                        tagsStore.remove(alias: alias)
                    }
                    store.remove(id: host.id)
                    hostPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    hostPendingDeletion = nil
                }
            } message: { _ in
                Text("This will remove the host from ~/.ssh/config.")
            }
            .alert(
                "Error",
                isPresented: errorBinding,
                presenting: store.loadError
            ) { _ in
                Button("OK") { store.loadError = nil }
            } message: { msg in
                Text(msg)
            }
            .alert(
                "Could not open terminal",
                isPresented: connectErrorBinding,
                presenting: connectError
            ) { _ in
                Button("OK") { connectError = nil }
            } message: { msg in
                Text(msg)
            }
            .sheet(item: $hostKeyWarning, onDismiss: {
                if let req = seedAfterWarningDismiss {
                    seedAfterWarningDismiss = nil
                    enqueueSeed(host: req.host, userOverride: req.userOverride)
                }
            }) { warning in
                HostKeyWarningSheet(
                    warning: warning,
                    onRemoveKey: { HostConnector.removeOldKey(for: warning, reachCache: reachCache) },
                    onReseed: {
                        seedAfterWarningDismiss = SeedRequest(host: warning.host, userOverride: warning.user)
                    },
                    onConnect: { connectAfterRemoval(warning) },
                    onBypassOnce: { bypass(warning, persist: false) },
                    onBypassPersist: { bypass(warning, persist: true) }
                )
            }
            .sheet(item: $presentedRelease, onDismiss: {
                if case .downloading = updater.state {
                    updater.cancelDownload()
                }
                updater.dismissTransient()
            }) { release in
                @Bindable var binding = updater
                UpdateAvailableSheet(checker: binding, release: release)
            }
            .alert("No update available", isPresented: standaloneInfoBinding) {
                Button("OK") { updater.dismissTransient() }
            } message: {
                Text("sshCM \(updater.currentVersionString) is the latest version.")
            }
            .alert("Update check failed", isPresented: standaloneErrorBinding) {
                Button("OK") { updater.dismissTransient() }
            } message: {
                if case .error(let msg) = updater.state {
                    Text(msg)
                }
            }
            .onChange(of: stateMarker) { _, _ in
                syncPresentedRelease()
            }
            .onAppear {
                syncPresentedRelease()
                drainPaletteBridge()
                let open = openWindow
                MainWindowOpener.open = { open(id: "main") }
                let openSettingsAction = openSettings
                SettingsOpener.open = { openSettingsAction() }
                let checker = updater
                UpdateCheckTrigger.trigger = {
                    Task { await checker.check(userInitiated: true) }
                }
                installTypeAheadMonitor()
                DispatchQueue.main.async { MainWindowCloseGuard.installOnMainWindows() }
            }
            .onDisappear { removeTypeAheadMonitor() }
            .task(id: probeFleetKey) {
                let snapshot = store.file.hosts
                for host in snapshot {
                    Task { await reachCache.runProbe(for: host) }
                }
            }
            .onChange(of: paletteBridge.pendingEdit) { _, newValue in
                guard let host = newValue else { return }
                hostBeingEdited = host
                paletteBridge.pendingEdit = nil
            }
            .onChange(of: paletteBridge.pendingDelete) { _, newValue in
                guard let host = newValue else { return }
                hostPendingDeletion = host
                paletteBridge.pendingDelete = nil
            }
            .onChange(of: paletteBridge.pendingAdd) { _, newValue in
                guard newValue else { return }
                showingAdd = true
                paletteBridge.pendingAdd = false
            }
            .onChange(of: paletteBridge.pendingKeyWarning) { _, newValue in
                guard let warning = newValue else { return }
                hostKeyWarning = warning
                paletteBridge.pendingKeyWarning = nil
            }
    }

    private var stateMarker: Int {
        switch updater.state {
        case .idle: return 0
        case .checking: return 1
        case .upToDate: return 2
        case .available(let r): return 3 &+ r.tag.hashValue
        case .downloading: return 4
        case .installing: return 5
        case .confirmUnsigned(let r): return 6 &+ r.tag.hashValue
        case .error(let m): return 7 &+ m.hashValue
        }
    }

    private func installTypeAheadMonitor() {
        guard typeAheadMonitor == nil else { return }
        typeAheadMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleTypeAhead(event)
        }
    }

    private func removeTypeAheadMonitor() {
        if let monitor = typeAheadMonitor {
            NSEvent.removeMonitor(monitor)
            typeAheadMonitor = nil
        }
    }

    private func handleTypeAhead(_ event: NSEvent) -> NSEvent? {
        guard let win = event.window, win === NSApp.mainWindow else { return event }
        guard win.attachedSheet == nil else { return event }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // In menu-bar (accessory) mode there is no app menu to process SwiftUI
        // `.keyboardShortcut`, so handle ⌘E / ⌘I here (works while the main
        // window is key). In Dock (.regular) mode the SwiftUI shortcuts handle
        // them and show the hint in the toolbar menu, so we defer to those.
        if NSApp.activationPolicy() == .accessory, mods == .command,
           let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "e":
                if !store.file.hosts.isEmpty { showingExport = true }
                return nil
            case "i":
                beginImport()
                return nil
            default:
                break
            }
        }

        if let responder = win.firstResponder, responder.isKind(of: NSText.self) {
            return event
        }
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            return event
        }

        switch event.keyCode {
        case 51: // Backspace
            guard !searchText.isEmpty else { return event }
            searchText.removeLast()
            return nil
        case 53: // Escape
            guard !searchText.isEmpty else { return event }
            searchText = ""
            return nil
        default:
            break
        }

        guard
            let chars = event.charactersIgnoringModifiers,
            let scalar = chars.unicodeScalars.first
        else { return event }
        // Skip control chars, DEL, and the NSEvent private-use range (arrows, function keys, etc.)
        if scalar.value < 0x20 || scalar.value == 0x7F { return event }
        if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return event }

        searchText.append(chars)
        return nil
    }

    private var jumpHostAliases: Set<String> {
        SSHHost.jumpHostAliases(in: store.file.hosts)
    }

    private func isJumpHost(_ host: SSHHost) -> Bool {
        !Set(host.aliases).isDisjoint(with: jumpHostAliases)
    }

    private var probeFleetKey: String {
        let keys = store.file.hosts
            .compactMap { ReachabilityCache.cacheKey(for: $0) }
            .sorted()
            .joined(separator: ",")
        return "\(reachCache.epoch)|\(keys)"
    }

    private func drainPaletteBridge() {
        if let host = paletteBridge.pendingEdit {
            hostBeingEdited = host
            paletteBridge.pendingEdit = nil
        }
        if let host = paletteBridge.pendingDelete {
            hostPendingDeletion = host
            paletteBridge.pendingDelete = nil
        }
        if paletteBridge.pendingAdd {
            showingAdd = true
            paletteBridge.pendingAdd = false
        }
        if let warning = paletteBridge.pendingKeyWarning {
            hostKeyWarning = warning
            paletteBridge.pendingKeyWarning = nil
        }
    }

    private func syncPresentedRelease() {
        switch updater.state {
        case .available(let release):
            if presentedRelease?.tag != release.tag {
                presentedRelease = release
            }
        case .upToDate, .idle:
            presentedRelease = nil
        case .checking, .downloading, .installing, .confirmUnsigned, .error:
            break
        }
    }

    private var standaloneInfoBinding: Binding<Bool> {
        Binding(
            get: { presentedRelease == nil && { if case .upToDate = updater.state { return true }; return false }() },
            set: { if !$0 { updater.dismissTransient() } }
        )
    }

    private var standaloneErrorBinding: Binding<Bool> {
        Binding(
            get: { presentedRelease == nil && { if case .error = updater.state { return true }; return false }() },
            set: { if !$0 { updater.dismissTransient() } }
        )
    }

    private var baseView: some View {
        hostsContent
            // Rebuild the grid/list when the active filters change so it
            // re-lays-out from the top — otherwise a stale scroll offset can clip
            // the first item after a filter is removed.
            .id(listIdentity)
            .frame(minWidth: 990, maxWidth: 1320, minHeight: 320)
            .navigationTitle("SSH Config Manager")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showOnlyReachable.toggle()
                    } label: {
                        Label(
                            showOnlyReachable ? "Show All Hosts" : "Show Only Reachable",
                            systemImage: showOnlyReachable ? "circle.fill" : "circle.dotted"
                        )
                    }
                    .tint(showOnlyReachable ? .green : nil)
                    .help(showOnlyReachable ? "Show all hosts" : "Show only reachable hosts")

                    Button {
                        viewModeRaw = (viewMode == .card ? HostsViewMode.list : .card).rawValue
                    } label: {
                        Label(
                            viewMode == .card ? "Switch to List" : "Switch to Grid",
                            systemImage: viewMode == .card ? "list.bullet" : "square.grid.2x2"
                        )
                    }
                    .help(viewMode == .card ? "Switch to list view" : "Switch to grid view")

                    Button {
                        reachCache.clear()
                        store.load()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Reload ~/.ssh/config and re-check reachability")

                    Menu {
                        Button {
                            showingExport = true
                        } label: {
                            Label("Export Hosts…", systemImage: "arrowshape.up.circle")
                        }
                        .keyboardShortcut("e", modifiers: .command)
                        .disabled(store.file.hosts.isEmpty)
                        Button {
                            beginImport()
                        } label: {
                            Label("Import Hosts…", systemImage: "arrowshape.down.circle")
                        }
                        .keyboardShortcut("i", modifiers: .command)
                    } label: {
                        Label("Import or Export", systemImage: "square.and.arrow.up.on.square")
                    }
                    .help("Export or import hosts as a portable JSON file")

                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Host", systemImage: "plus")
                    }
                    .help("Add a new host")
                }
            }
            .searchable(text: $searchText, prompt: "Filter hosts")
            .overlay(alignment: .center) {
                if store.file.hosts.isEmpty {
                    emptyState
                } else if sortedHosts.isEmpty {
                    noMatchesState
                }
            }
    }

    /// Picks a JSON file, decodes it, and opens the import selection sheet. The
    /// open panel is modal and returns synchronously, so this stays sequential.
    private func beginImport() {
        guard let url = FilePicker.pickImportFile() else { return }
        do {
            let data = try Data(contentsOf: url)
            let document = try HostPortability.decode(data)
            importSession = ImportSession(document: document)
        } catch {
            importError = "Could not read hosts file: \(error.localizedDescription)"
        }
    }

    private func considerKeySeeds(host: SSHHost, isNew: Bool, addedAlternateUsers: [String]) async {
        let target = [host.hostName, host.aliases.first]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let target else { return }
        let port = host.port ?? 22
        guard await Reachability.probe(host: target, port: port) else { return }

        var requests: [SeedRequest] = []
        if isNew {
            requests.append(SeedRequest(host: host, userOverride: nil))
        }
        for user in addedAlternateUsers {
            requests.append(SeedRequest(host: host, userOverride: user))
        }
        guard !requests.isEmpty else { return }
        pendingSeedRequests.append(contentsOf: requests)
        if currentSeedRequest == nil {
            dequeueNextSeed()
        }
    }

    private func dequeueNextSeed() {
        guard currentSeedRequest == nil, !pendingSeedRequests.isEmpty else { return }
        currentSeedRequest = pendingSeedRequests.removeFirst()
    }

    private func connect(
        to host: SSHHost,
        as user: String? = nil,
        localForwards: [String] = [],
        remoteForwards: [String] = []
    ) {
        guard let alias = host.aliases.first, !alias.isEmpty else {
            connectError = "Host has no alias to connect to."
            return
        }
        do {
            if let warning = try HostConnector.connect(
                to: host,
                as: user,
                localForwards: localForwards,
                remoteForwards: remoteForwards,
                reachCache: reachCache,
                bypassStore: bypassStore,
                terminalAppPath: terminalAppPath
            ) {
                hostKeyWarning = warning
            }
        } catch {
            connectError = error.localizedDescription
        }
    }

    /// Connects applying the host's stored forwards for the requested directions.
    private func connectForwarding(to host: SSHHost, includeLocal: Bool, includeRemote: Bool) {
        connect(
            to: host,
            localForwards: includeLocal ? host.localForwards.map(\.spec) : [],
            remoteForwards: includeRemote ? host.remoteForwards.map(\.spec) : []
        )
    }

    private func connectVNC(to host: SSHHost) {
        guard let target = host.hostName?.trimmingCharacters(in: .whitespaces), !target.isEmpty else {
            connectError = "Host has no HostName to connect to via VNC."
            return
        }
        let remoteApp = remoteAppsStore.selectableApps(screenSharingPath: macOSVNCAppPath)
            .first { $0.name == host.remoteApp }
        do {
            try VNCLauncher.launch(
                toHost: target,
                port: host.vncPort ?? 5900,
                remoteApp: remoteApp,
                user: host.user
            )
        } catch {
            connectError = error.localizedDescription
        }
    }

    private func connectSMB(to host: SSHHost) {
        guard let target = host.hostName?.trimmingCharacters(in: .whitespaces), !target.isEmpty else {
            connectError = "Host has no HostName to connect to via SMB."
            return
        }
        do {
            try SMBConnector.connect(toHost: target)
        } catch {
            connectError = error.localizedDescription
        }
    }

    /// Connects normally after the user removed a changed host key.
    private func connectAfterRemoval(_ warning: HostConnector.KeyWarning) {
        do {
            try HostConnector.connectNormally(warning, terminalAppPath: terminalAppPath)
        } catch {
            connectError = error.localizedDescription
        }
    }

    /// Connects with host-key checking disabled, optionally persisting the bypass.
    private func bypass(_ warning: HostConnector.KeyWarning, persist: Bool) {
        do {
            try HostConnector.connectBypassing(
                warning,
                persist: persist,
                bypassStore: bypassStore,
                terminalAppPath: terminalAppPath
            )
        } catch {
            connectError = error.localizedDescription
        }
    }

    /// Queues a key-seeding sheet for `host`. Used after a re-imaged host's
    /// changed key is removed, to offer re-copying the public key.
    private func enqueueSeed(host: SSHHost, userOverride: String?) {
        pendingSeedRequests.append(SeedRequest(host: host, userOverride: userOverride))
        if currentSeedRequest == nil {
            dequeueNextSeed()
        }
    }

    private var connectErrorBinding: Binding<Bool> {
        Binding(
            get: { connectError != nil },
            set: { if !$0 { connectError = nil } }
        )
    }

    private var confirmationTitle: String {
        if let h = hostPendingDeletion {
            return "Remove \(h.title)?"
        }
        return "Remove host?"
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { hostPendingDeletion != nil },
            set: { if !$0 { hostPendingDeletion = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.loadError != nil },
            set: { if !$0 { store.loadError = nil } }
        )
    }

    private var sortedHosts: [SSHHost] {
        let untaggedRank = HostTag.allCases.count
        return HostListFilter(searchText: searchText, showOnlyReachable: showOnlyReachable)
            .apply(
                hosts: store.file.hosts,
                isFavorite: { favorites.isFavorite($0) },
                tagRank: { alias in
                    tagsStore.tag(for: alias).map { tagsStore.rank(for: $0) } ?? untaggedRank
                },
                tagName: { alias in
                    tagsStore.tag(for: alias).map { tagsStore.displayName(for: $0) }
                },
                isReachable: { host in
                    guard let key = ReachabilityCache.cacheKey(for: host) else { return false }
                    return reachCache.status(for: key) == .reachable
                }
            )
    }

    @ViewBuilder
    private var hostsContent: some View {
        switch viewMode {
        case .card: hostGrid
        case .list: hostList
        }
    }

    /// Identity for the grid/list, so it rebuilds (and scrolls to top) whenever
    /// the view mode or active filters change.
    private var listIdentity: String {
        "\(viewModeRaw)|\(showOnlyReachable)|\(searchText)"
    }

    private var hostGrid: some View {
        GeometryReader { proxy in
            let columnCount = max(1, Int(proxy.size.width / 330))
            let columns = Array(repeating: GridItem(.fixed(330), spacing: 0), count: columnCount)
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    ForEach(sortedHosts) { host in
                        HostCardView(
                            host: host,
                            isJumpHost: isJumpHost(host),
                            onEdit: { hostBeingEdited = host },
                            onDelete: { hostPendingDeletion = host },
                            onConnect: { connect(to: host) },
                            onConnectAs: { user in connect(to: host, as: user) },
                            onConnectForwarding: { local, remote in
                                connectForwarding(to: host, includeLocal: local, includeRemote: remote)
                            },
                            onConnectVNC: { connectVNC(to: host) },
                            onConnectSMB: { connectSMB(to: host) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var hostList: some View {
        List {
            ForEach(sortedHosts) { host in
                HostRowView(
                    host: host,
                    isJumpHost: isJumpHost(host),
                    onEdit: { hostBeingEdited = host },
                    onDelete: { hostPendingDeletion = host },
                    onConnect: { connect(to: host) },
                    onConnectAs: { user in connect(to: host, as: user) },
                    onConnectForwarding: { local, remote in
                        connectForwarding(to: host, includeLocal: local, includeRemote: remote)
                    },
                    onConnectVNC: { connectVNC(to: host) },
                    onConnectSMB: { connectSMB(to: host) }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        hostPendingDeletion = host
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No SSH hosts yet")
                .font(.title3)
            Text("Click + to add a host. Changes are written to ~/.ssh/config.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No matching hosts")
                .font(.title3)
            Text(noMatchesDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var noMatchesDetail: String {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        switch (query.isEmpty, showOnlyReachable) {
        case (false, true):
            return "No reachable hosts match \"\(query)\"."
        case (false, false):
            return "No hosts match \"\(query)\"."
        case (true, true):
            return "No hosts are currently reachable."
        case (true, false):
            return "No matching hosts."
        }
    }
}

#Preview {
    ContentView()
        .environment(ConfigStore())
        .environment(RemoteAppsStore())
}
