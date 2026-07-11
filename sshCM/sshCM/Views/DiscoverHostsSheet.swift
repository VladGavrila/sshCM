import SwiftUI

/// Scans the local network for hosts with SSH (port 22) open and lets the user
/// pick which responders to add to `~/.ssh/config`. The subnet is auto-detected
/// and prefilled but editable; picked hosts are written as
/// `SSHHost(aliases:hostName:user:)` entries via the shared `ConfigStore.add`
/// path, with a shared "Connect as" user applied to every host added from this
/// scan (mirroring `AddHostSheet`, which also requires a non-empty user —
/// without one, a plain `ssh <alias>` falls back to the local macOS account
/// name instead of anything meaningful on the remote host).
struct DiscoverHostsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var store

    @State private var scanner = HostDiscoveryScanner()
    @State private var rangeText: String = ""
    @State private var connectAsUser: String = NSUserName()
    @State private var parseError: String?
    @State private var scanTask: Task<Void, Never>?
    @State private var didPrefill = false

    var body: some View {
        @Bindable var scanner = scanner
        return VStack(spacing: 0) {
            header
            Divider()
            content(scanner: $scanner)
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear(perform: prefillRange)
        .onDisappear { scanTask?.cancel() }
    }

    // MARK: - Header (range + scan control)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discover hosts")
                .font(.headline)
            Text("Scan a network range for machines with SSH (port 22) open.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Range", text: $rangeText, prompt: Text("192.168.1.0/24"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(scanner.isScanning)
                    .onSubmit { if !scanner.isScanning { startScan() } }
                if scanner.isScanning {
                    Button("Stop", action: stopScan)
                } else {
                    Button("Scan", action: startScan)
                        .disabled(rangeText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Text("Connect as")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("User", text: $connectAsUser, prompt: Text("e.g. pi, ubuntu"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            Text("Applied to every host you add from this scan — edit each host afterward if they use different accounts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: - Content (progress + results)

    @ViewBuilder
    private func content(scanner: Bindable<HostDiscoveryScanner>) -> some View {
        VStack(spacing: 0) {
            statusBar
            if scanner.wrappedValue.results.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(scanner.results) { $row in
                        resultRow($row)
                    }
                }
            }
        }
    }

    private var statusBar: some View {
        Group {
            switch scanner.phase {
            case .idle:
                EmptyView()
            case let .scanning(probed, total):
                HStack(spacing: 8) {
                    ProgressView(value: Double(probed), total: Double(max(total, 1)))
                    Text("Scanning \(probed)/\(total)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            case let .done(found):
                Text(found == 0
                     ? "No hosts with SSH open in that range."
                     : "Found \(found) host\(found == 1 ? "" : "s") with SSH open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(scanner.isScanning ? "Scanning…" : "Enter a range and press Scan.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultRow(_ row: Binding<HostDiscoveryScanner.Discovered>) -> some View {
        let value = row.wrappedValue
        let error = aliasError(for: value)
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: row.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(value.alreadyInConfig)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Alias", text: row.alias)
                    .textFieldStyle(.roundedBorder)
                    .disabled(value.alreadyInConfig)
                    .onChange(of: row.wrappedValue.alias) { _, newValue in
                        let sanitized = SSHHost.sanitizeAliasToken(newValue)
                        if sanitized != newValue { row.wrappedValue.alias = sanitized }
                    }
                if value.isSelected, !value.alreadyInConfig, let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value.ip)
                    .font(.callout.monospaced())
                if value.alreadyInConfig {
                    Text("In config")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let name = value.name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(value.alreadyInConfig ? 0.55 : 1)
        .padding(.vertical, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                scanTask?.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Add Selected (\(selectedRows.count))", action: addSelected)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
        }
        .padding(12)
    }

    // MARK: - Selection / validation

    private var selectedRows: [HostDiscoveryScanner.Discovered] {
        scanner.results.filter { $0.isSelected && !$0.alreadyInConfig }
    }

    private var canAdd: Bool {
        !connectAsUser.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectedRows.isEmpty
            && selectedRows.allSatisfy { aliasError(for: $0) == nil }
    }

    /// Mirrors `AddHostSheet.aliasError`: an alias must be a single legal token,
    /// unique across the config, and unique among the other rows being added.
    private func aliasError(for row: HostDiscoveryScanner.Discovered) -> String? {
        let value = row.alias.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return "Alias required." }
        guard HostsFileBlock.isPublishableHostname(value) else {
            return "Use letters, digits, - . _"
        }
        if store.file.hosts.contains(where: { $0.aliases.contains(value) }) {
            return "Already used by another host."
        }
        let dupInScan = scanner.results.contains { other in
            other.id != row.id && other.isSelected && !other.alreadyInConfig
                && other.alias.trimmingCharacters(in: .whitespaces) == value
        }
        if dupInScan { return "Duplicate alias in this scan." }
        return nil
    }

    // MARK: - Actions

    private func prefillRange() {
        guard !didPrefill else { return }
        didPrefill = true
        if rangeText.isEmpty,
           let net = LocalNetwork.primaryIPv4(),
           let suggestion = SubnetScan.defaultRange(ip: net.ip, netmask: net.netmask) {
            rangeText = suggestion
        }
    }

    private func startScan() {
        switch SubnetScan.parseScanRange(rangeText) {
        case let .failure(error):
            parseError = error.message
        case let .success(candidates):
            parseError = nil
            let existingHostNames = Set(store.file.hosts.compactMap { $0.hostName })
            let existingAliases = Set(store.file.hosts.flatMap { $0.aliases })
            scanTask?.cancel()
            let scanner = scanner
            scanTask = Task {
                await scanner.scan(
                    candidates: candidates,
                    existingHostNames: existingHostNames,
                    existingAliases: existingAliases
                )
            }
        }
    }

    private func stopScan() {
        scanTask?.cancel()
    }

    private func addSelected() {
        let picks = selectedRows
        let user = connectAsUser.trimmingCharacters(in: .whitespaces)
        guard !picks.isEmpty, !user.isEmpty else { return }
        for pick in picks {
            let alias = pick.alias.trimmingCharacters(in: .whitespaces)
            guard !alias.isEmpty else { continue }
            // Batch: skip per-host `/etc/hosts` publishing, then publish once.
            store.add(SSHHost(aliases: [alias], hostName: pick.ip, user: user), publish: false)
        }
        store.publishHostsIfEnabled()
        dismiss()
    }
}
