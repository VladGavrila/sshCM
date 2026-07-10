import SwiftUI

/// Sheet shown after a hosts JSON file has been picked and decoded. Lets the
/// user pick all-or-some hosts to import. Hosts whose primary alias already
/// exists are flagged and, on import, resolved one at a time (use imported vs
/// keep current).
struct ImportHostsSheet: View {
    let document: HostExportDocument

    @Environment(ConfigStore.self) private var store
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ReachabilityCache.self) private var reachCache
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID>
    @State private var pendingConflicts: [ExportedHost] = []
    @State private var currentConflict: ExportedHost?
    @State private var totalConflicts = 0
    @State private var filterText = ""
    @State private var reachableOnly = false
    @State private var newOnly = false
    /// When true the sheet shows the compact reconciliation prompt instead of the
    /// picker (switched immediately on Import).
    @State private var compact = false

    init(document: HostExportDocument) {
        self.document = document
        _selected = State(initialValue: Set(document.hosts.map(\.id)))
    }

    private var existingAliases: Set<String> {
        Set(store.file.hosts.compactMap { $0.aliases.first })
    }

    /// The primary alias as it will actually be stored — sanitized to the same
    /// character set the add/edit form enforces — so conflict detection and
    /// metadata keying match what lands in `~/.ssh/config`.
    private func storedAlias(_ host: ExportedHost) -> String? {
        guard let raw = host.primaryAlias else { return nil }
        let sanitized = SSHHost.sanitizeAliasToken(raw)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func conflicts(_ host: ExportedHost) -> Bool {
        guard let alias = storedAlias(host) else { return false }
        return existingAliases.contains(alias)
    }

    /// Live reachability for an imported host. The probe is keyed by `host:port`
    /// (see `ReachabilityCache.cacheKey`), so it shares results with any matching
    /// host already in the config. `.checking` is shown until the probe lands.
    private func reachStatus(for host: ExportedHost) -> ReachStatus {
        guard let key = ReachabilityCache.cacheKey(for: host.toSSHHost()) else { return .unreachable }
        return reachCache.status(for: key) ?? .checking
    }

    /// Hosts currently shown given the filter text, the new-only and the
    /// reachable-only toggles. The filter scopes the import: only selected hosts
    /// that are visible are imported (see `selectedVisibleHosts`). The `selected`
    /// set itself is untouched, so hiding then re-showing preserves checkboxes.
    private var visibleHosts: [ExportedHost] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        return document.hosts.filter { host in
            if newOnly && conflicts(host) { return false }
            if reachableOnly && reachStatus(for: host) != .reachable { return false }
            guard !query.isEmpty else { return true }
            let tagName = host.tag.map { tagsStore.displayName(for: $0) }
            var haystacks: [String?] = [
                host.aliases.joined(separator: " "), host.hostName, host.user, host.proxyJump, tagName
            ]
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

    /// The hosts that will actually be imported: selected *and* currently shown.
    /// Hosts hidden by a filter are excluded, so the filter scopes the import.
    private var selectedVisibleHosts: [ExportedHost] {
        visibleHosts.filter { selected.contains($0.id) }
    }

    /// Identity for the list, so it rebuilds (and scrolls to top) whenever the
    /// active filters change.
    private var filterSignature: String {
        "\(newOnly)|\(reachableOnly)|\(filterText)"
    }

    private var emptyMessage: String {
        if filterText.isEmpty {
            switch (newOnly, reachableOnly) {
            case (true, true): return "No new, reachable hosts."
            case (true, false): return "All hosts already exist."
            case (false, true): return "No reachable hosts."
            case (false, false): return "No hosts to import."
            }
        }
        return "No hosts match the filter."
    }

    var body: some View {
        Group {
            if compact, let conflict = currentConflict {
                conflictPrompt(conflict)
            } else {
                pickerContent
            }
        }
        .frame(width: compact ? 380 : 600, height: compact ? 300 : 440)
        .task {
            // Probe each host to be imported so the rows show live reachability,
            // matching the export sheet and the main window. Idempotent and
            // keyed by host:port, so it reuses results for hosts already present.
            for host in document.hosts {
                Task { await reachCache.runProbe(for: host.toSSHHost()) }
            }
        }
    }

    private var pickerContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Import Hosts")
                        .font(.headline)
                    Spacer()
                    Text("\(selectedVisibleHosts.count) of \(document.hosts.count) selected")
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
                    Toggle("New only", isOn: $newOnly)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .help("Hide hosts whose alias already exists in ~/.ssh/config")
                    Toggle("Reachable only", isOn: $reachableOnly)
                        .toggleStyle(.checkbox)
                        .fixedSize()
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
                        title: host.aliases.joined(separator: " "),
                        user: host.user,
                        hostName: host.hostName,
                        tag: host.tag,
                        reachStatus: reachStatus(for: host),
                        favorite: host.favorite,
                        badge: conflicts(host) ? "already exists" : nil,
                        isOn: Binding(
                            get: { selected.contains(host.id) },
                            set: { if $0 { selected.insert(host.id) } else { selected.remove(host.id) } }
                        )
                    )
                }
            }
            // Reset the list's identity when the filter set changes so SwiftUI
            // re-lays-out from the top — otherwise a stale scroll offset can clip
            // the first row after toggling filters.
            .id(filterSignature)
            .overlay {
                if visibleHosts.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import", action: beginImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedVisibleHosts.isEmpty)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The conflict prompt shown in place of the picker (the picker is hidden
    /// while reconciling). Plain sheet background, centered, styled to match the
    /// import sheet — the "x of y" uses the same caption/secondary as the header.
    private func conflictPrompt(_ conflict: ExportedHost) -> some View {
        VStack(spacing: 10) {
            Text("Host “\(conflict.primaryAlias ?? "")” already exists")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Replace the existing host's settings with the imported one, or keep what you have?")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(conflictProgress)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Button { resolve(conflict, useImported: true) } label: {
                    Text("Use Imported").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button { resolve(conflict, useImported: false) } label: {
                    Text("Keep Current").frame(maxWidth: .infinity)
                }

                Button(role: .cancel) { cancelReconciliation() } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "1 of 3"-style progress through the conflict queue, shown above the
    /// buttons — matching the "x of y selected" wording in the sheet header.
    private var conflictProgress: String {
        let index = totalConflicts - pendingConflicts.count
        return "\(index) of \(totalConflicts)"
    }

    private func beginImport() {
        let chosen = selectedVisibleHosts
        let conflicting = chosen.filter(conflicts)
        let fresh = chosen.filter { !conflicts($0) }

        for host in fresh {
            applyNew(host)
        }

        totalConflicts = conflicting.count
        guard !conflicting.isEmpty else {
            finishReconciliation()
            return
        }
        pendingConflicts = conflicting
        currentConflict = pendingConflicts.removeFirst()
        // Switch straight to the compact prompt — no fade.
        compact = true
    }

    /// Pops the next conflict to resolve, or finishes when none remain.
    private func advanceConflicts() {
        if pendingConflicts.isEmpty {
            finishReconciliation()
        } else {
            currentConflict = pendingConflicts.removeFirst()
        }
    }

    /// Ends reconciliation and closes the sheet. The `/etc/hosts` sync is deferred
    /// to here so the whole import costs at most a single admin prompt. The sheet
    /// just dismisses at its current (compact) size — no resize back to the picker.
    private func finishReconciliation() {
        store.publishHostsIfEnabled()
        dismiss()
    }

    /// Aborts the remaining conflict reconciliation. Hosts already imported (the
    /// fresh ones and any conflicts already resolved) stay applied; the unhandled
    /// conflicts are left untouched. Dismisses without resizing back.
    private func cancelReconciliation() {
        finishReconciliation()
    }

    private func resolve(_ host: ExportedHost, useImported: Bool) {
        if useImported {
            applyReplace(host)
        }
        // "Keep Current" simply skips. The overlay is a plain conditional view,
        // so advancing to the next conflict is just a state change — no alert
        // re-present race to work around.
        advanceConflicts()
    }

    /// Adds a brand-new host (fresh UUID). The imported color tag and favorite
    /// flag travel on the host itself (`toSSHHost`), so there's no separate
    /// metadata step. Publishing to `/etc/hosts` is deferred — see
    /// `advanceConflicts()`.
    private func applyNew(_ host: ExportedHost) {
        store.add(host.toSSHHost().sanitizedForImport(), publish: false)
    }

    /// Overwrites the existing host that shares this primary alias, reusing its
    /// UUID so any in-flight references stay valid.
    private func applyReplace(_ host: ExportedHost) {
        guard let alias = storedAlias(host),
              let existing = store.file.hosts.first(where: { $0.aliases.first == alias })
        else {
            applyNew(host)
            return
        }
        store.update(host.toSSHHost(id: existing.id).sanitizedForImport(), publish: false)
    }
}
