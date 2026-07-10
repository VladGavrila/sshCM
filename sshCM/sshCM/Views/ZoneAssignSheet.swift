import SwiftUI

/// Bulk zone assignment sheet, opened from the Zones settings tab for one
/// zone at a time. Mirrors `ExportHostsSheet`'s search + checkbox-list shape,
/// reusing `HostSelectionRow`. Since a host belongs to at most one zone,
/// checking a host that's currently in a *different* zone moves it — that
/// other zone is shown as a secondary badge so the move isn't a surprise.
struct ZoneAssignSheet: View {
    let zone: String
    let hosts: [SSHHost]

    @Environment(ConfigStore.self) private var store
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ReachabilityCache.self) private var reachCache
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID>
    @State private var filterText = ""

    init(zone: String, hosts: [SSHHost]) {
        self.zone = zone
        self.hosts = hosts
        _selected = State(initialValue: Set(hosts.filter { $0.zone == zone }.map(\.id)))
    }

    private var visibleHosts: [SSHHost] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return hosts }
        return hosts.filter { host in
            let tagName = host.tag.map { tagsStore.displayName(for: $0) }
            var haystacks: [String?] = [host.title, host.hostName, host.user, host.proxyJump, tagName, host.zone]
            haystacks.append(contentsOf: host.searchAliases.map { Optional($0) })
            return haystacks.contains { value in
                guard let value, !value.isEmpty else { return false }
                return value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var allVisibleSelected: Bool {
        let visible = visibleHosts
        return !visible.isEmpty && visible.allSatisfy { selected.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Assign Hosts to \(zone)")
                        .font(.headline)
                    Spacer()
                    Text("\(selected.count) of \(hosts.count) selected")
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
                        tag: host.tag,
                        reachStatus: reachStatus(for: host),
                        favorite: host.isFavorite,
                        badge: otherZoneBadge(for: host),
                        isOn: Binding(
                            get: { selected.contains(host.id) },
                            set: { if $0 { selected.insert(host.id) } else { selected.remove(host.id) } }
                        )
                    )
                }
            }
            .id(filterText)
            .overlay {
                if visibleHosts.isEmpty {
                    Text("No hosts match the filter.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 600, minHeight: 380)
    }

    private func otherZoneBadge(for host: SSHHost) -> String? {
        guard let hostZone = host.zone, hostZone != zone else { return nil }
        return hostZone
    }

    private func reachStatus(for host: SSHHost) -> ReachStatus {
        guard let key = ReachabilityCache.cacheKey(for: host) else { return .unreachable }
        return reachCache.status(for: key) ?? .checking
    }

    private func apply() {
        store.updateAll { host in
            if selected.contains(host.id) {
                host.zone = zone
            } else if host.zone == zone {
                host.zone = nil
            }
        }
        dismiss()
    }
}
