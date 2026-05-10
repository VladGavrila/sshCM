import SwiftUI

struct ContentView: View {
    @Environment(ConfigStore.self) private var store

    @AppStorage("defaultTerminalAppPath") private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath

    @State private var showingAdd = false
    @State private var hostBeingEdited: SSHHost?
    @State private var hostPendingDeletion: SSHHost?
    @State private var searchText: String = ""
    @State private var connectError: String?

    var body: some View {
        baseView
            .sheet(isPresented: $showingAdd) {
                AddHostSheet()
                    .environment(store)
            }
            .sheet(item: $hostBeingEdited) { (host: SSHHost) in
                AddHostSheet(editing: host)
                    .environment(store)
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: deletionBinding,
                presenting: hostPendingDeletion
            ) { host in
                Button("Remove \"\(host.title)\"", role: .destructive) {
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
    }

    private var baseView: some View {
        hostGrid
            .frame(minWidth: 990, maxWidth: 1320, minHeight: 320)
            .navigationTitle("SSH Config Manager")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        store.load()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Reload ~/.ssh/config")

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
        let sorted = store.file.hosts.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { host in
            let haystacks: [String?] = [
                host.title,
                host.hostName,
                host.user,
                host.identityFile,
                host.proxyJump,
                host.port.map(String.init)
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
