import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(ConfigStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ReachabilityCache.self) private var reachCache
    @Environment(UpdateChecker.self) private var updater
    @Environment(PaletteBridge.self) private var paletteBridge

    @AppStorage("defaultTerminalAppPath") private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var showingAdd = false
    @State private var hostBeingEdited: SSHHost?
    @State private var hostPendingDeletion: SSHHost?
    @State private var hostPendingKeySeed: SSHHost?
    @State private var searchText: String = ""
    @State private var connectError: String?
    @State private var presentedRelease: UpdateChecker.Release?

    var body: some View {
        baseView
            .background(
                Button(action: { CommandPaletteController.shared.toggle() }) { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut("k", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            )
            .sheet(isPresented: $showingAdd) {
                AddHostSheet(onAdded: { host in
                    Task { await considerKeySeed(for: host) }
                })
                .environment(store)
                .environment(tagsStore)
            }
            .sheet(item: $hostPendingKeySeed) { (host: SSHHost) in
                SeedKeySheet(host: host)
            }
            .sheet(item: $hostBeingEdited) { (host: SSHHost) in
                AddHostSheet(editing: host)
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
    }

    private var stateMarker: Int {
        switch updater.state {
        case .idle: return 0
        case .checking: return 1
        case .upToDate: return 2
        case .available(let r): return 3 &+ r.tag.hashValue
        case .downloading: return 4
        case .installing: return 5
        case .error(let m): return 6 &+ m.hashValue
        }
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
    }

    private func syncPresentedRelease() {
        switch updater.state {
        case .available(let release):
            if presentedRelease?.tag != release.tag {
                presentedRelease = release
            }
        case .upToDate, .idle:
            presentedRelease = nil
        case .checking, .downloading, .installing, .error:
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
        hostGrid
            .frame(minWidth: 990, maxWidth: 1320, minHeight: 320)
            .navigationTitle("SSH Config Manager")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        reachCache.clear()
                        store.load()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Reload ~/.ssh/config and re-check reachability")

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

    private func considerKeySeed(for host: SSHHost) async {
        let target = [host.hostName, host.aliases.first]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let target else { return }
        let port = host.port ?? 22
        guard await Reachability.probe(host: target, port: port) else { return }
        hostPendingKeySeed = host
    }

    private func connect(to host: SSHHost) {
        guard let alias = host.aliases.first, !alias.isEmpty else {
            connectError = "Host has no alias to connect to."
            return
        }
        do {
            try TerminalLauncher.launchSSH(toAlias: alias, terminalAppPath: terminalAppPath)
        } catch {
            connectError = error.localizedDescription
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

        let sorted = store.file.hosts.sorted { a, b in
            let aAlias = a.aliases.first ?? ""
            let bAlias = b.aliases.first ?? ""

            let aFav = favorites.isFavorite(aAlias)
            let bFav = favorites.isFavorite(bAlias)
            if aFav != bFav { return aFav }

            let aTagRank = tagsStore.tag(for: aAlias).map { tagsStore.rank(for: $0) } ?? untaggedRank
            let bTagRank = tagsStore.tag(for: bAlias).map { tagsStore.rank(for: $0) } ?? untaggedRank
            if aTagRank != bTagRank { return aTagRank < bTagRank }

            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { host in
            let tagName = host.aliases.first
                .flatMap { tagsStore.tag(for: $0) }
                .map { tagsStore.displayName(for: $0) }
            let haystacks: [String?] = [
                host.title,
                host.hostName,
                host.user,
                host.identityFile,
                host.proxyJump,
                host.port.map(String.init),
                tagName
            ]
            return haystacks.contains { value in
                guard let value, !value.isEmpty else { return false }
                return value.localizedCaseInsensitiveContains(query)
            }
        }
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
                            onEdit: { hostBeingEdited = host },
                            onDelete: { hostPendingDeletion = host },
                            onConnect: { connect(to: host) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
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
            Text("No hosts match \"\(searchText)\".")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
        .environment(ConfigStore())
}
