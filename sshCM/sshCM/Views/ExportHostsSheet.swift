import SwiftUI

/// Sheet that lets the user pick all-or-some hosts and write them (with their
/// tag/favorite metadata) to a portable JSON file via a save panel.
struct ExportHostsSheet: View {
    let hosts: [SSHHost]

    @Environment(TagsStore.self) private var tagsStore
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ReachabilityCache.self) private var reachCache
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID>
    @State private var exportError: String?
    @State private var filterText = ""
    @State private var reachableOnly = false

    init(hosts: [SSHHost]) {
        self.hosts = hosts
        _selected = State(initialValue: Set(hosts.map(\.id)))
    }

    /// Hosts currently shown given the filter text and the reachable-only toggle.
    /// The filter scopes the export: only selected hosts that are visible are
    /// written (see `selectedVisibleHosts`). The `selected` set itself is left
    /// untouched, so hiding then re-showing a host preserves its checkbox state.
    private var visibleHosts: [SSHHost] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        return hosts.filter { host in
            if reachableOnly {
                guard let key = ReachabilityCache.cacheKey(for: host),
                      reachCache.status(for: key) == .reachable else { return false }
            }
            guard !query.isEmpty else { return true }
            let tagName = host.aliases.first
                .flatMap { tagsStore.tag(for: $0) }
                .map { tagsStore.displayName(for: $0) }
            var haystacks: [String?] = [host.title, host.hostName, host.user, host.proxyJump, tagName]
            haystacks.append(contentsOf: host.searchAliases.map { Optional($0) })
            return haystacks.contains { value in
                guard let value, !value.isEmpty else { return false }
                return value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    /// True when every currently-visible host is already selected.
    private var allVisibleSelected: Bool {
        let visible = visibleHosts
        return !visible.isEmpty && visible.allSatisfy { selected.contains($0.id) }
    }

    /// The hosts that will actually be exported: selected *and* currently shown,
    /// so the filter scopes the export (matches the import sheet).
    private var selectedVisibleHosts: [SSHHost] {
        visibleHosts.filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Export Hosts")
                        .font(.headline)
                    Spacer()
                    Text("\(selectedVisibleHosts.count) of \(hosts.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter hosts", text: $filterText)
                        .textFieldStyle(.plain)
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().frame(height: 16)
                    Toggle("Reachable only", isOn: $reachableOnly)
                        .toggleStyle(.checkbox)
                    Button(allVisibleSelected ? "Deselect All" : "Select All") {
                        let ids = visibleHosts.map(\.id)
                        if allVisibleSelected {
                            ids.forEach { selected.remove($0) }
                        } else {
                            selected.formUnion(ids)
                        }
                    }
                    .disabled(visibleHosts.isEmpty)
                }
            }
            .padding(12)

            Divider()

            List {
                ForEach(visibleHosts) { host in
                    HostSelectionRow(
                        title: host.title,
                        user: host.user,
                        hostName: host.hostName,
                        tag: host.aliases.first.flatMap { tagsStore.tag(for: $0) },
                        reachStatus: reachStatus(for: host),
                        favorite: host.aliases.first.map { favorites.isFavorite($0) } ?? false,
                        badge: nil,
                        isOn: Binding(
                            get: { selected.contains(host.id) },
                            set: { if $0 { selected.insert(host.id) } else { selected.remove(host.id) } }
                        )
                    )
                }
            }
            .id("\(reachableOnly)|\(filterText)")
            .overlay {
                if visibleHosts.isEmpty {
                    Text(reachableOnly && filterText.isEmpty
                         ? "No reachable hosts."
                         : "No hosts match the filter.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…", action: export)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedVisibleHosts.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 600, minHeight: 380)
        .alert(
            "Export Failed",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func export() {
        let chosen = selectedVisibleHosts
        guard !chosen.isEmpty else { return }

        let document = HostPortability.makeDocument(
            hosts: chosen,
            tagsStore: tagsStore,
            favorites: favorites
        )

        let data: Data
        do {
            data = try HostPortability.encode(document)
        } catch {
            exportError = "Could not encode hosts: \(error.localizedDescription)"
            return
        }

        guard let url = FilePicker.pickExportDestination(suggestedName: defaultFileName()) else {
            return // user cancelled the save panel; keep the sheet open
        }

        do {
            try data.write(to: url, options: .atomic)
            dismiss()
        } catch {
            exportError = "Could not write file: \(error.localizedDescription)"
        }
    }

    private func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "sshcm-hosts-\(formatter.string(from: Date())).json"
    }

    /// Live reachability for a host, matching `HostRowView`'s logic.
    private func reachStatus(for host: SSHHost) -> ReachStatus {
        guard let key = ReachabilityCache.cacheKey(for: host) else { return .unreachable }
        return reachCache.status(for: key) ?? .checking
    }
}
