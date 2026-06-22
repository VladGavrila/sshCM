import SwiftUI

struct CommandPaletteView: View {
    let hosts: [SSHHost]
    let onConnect: (SSHHost, String?) -> Void
    /// Connect applying the host's stored forwards: `(host, user, includeLocal, includeRemote)`.
    let onConnectForwarding: (SSHHost, String?, Bool, Bool) -> Void
    let onConnectVNC: (SSHHost) -> Void
    let onEdit: (SSHHost) -> Void
    let onCopy: (SSHHost) -> Void
    let onCopyIP: (SSHHost) -> Void
    let onDelete: (SSHHost) -> Void
    let onClose: () -> Void

    @Environment(FavoritesStore.self) private var favorites
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ReachabilityCache.self) private var reachCache

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var userPickerHost: SSHHost?
    @State private var userPickerIndex: Int = 0
    @FocusState private var queryFocused: Bool

    private let maxResults = 8
    private let approxRowHeight: CGFloat = 46
    private let minVisibleRows: CGFloat = 4
    private let maxVisibleRows: CGFloat = 7

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search hosts…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($queryFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Group {
                if let host = userPickerHost {
                    userPickerContent(for: host)
                } else if results.isEmpty {
                    Text(hosts.isEmpty ? "No hosts in ~/.ssh/config." : "No matches for \"\(query)\".")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, host in
                                    row(for: host, index: index)
                                        .id(host.id)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        .onChange(of: selectedIndex) { _, newValue in
                            if results.indices.contains(newValue) {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    proxy.scrollTo(results[newValue].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(
                minHeight: approxRowHeight * minVisibleRows,
                maxHeight: approxRowHeight * maxVisibleRows,
                alignment: .top
            )

            Divider()

            HStack(spacing: 14) {
                if userPickerHost != nil {
                    hint("↵", "Connect")
                    hint("Esc", "Back")
                } else {
                    hint("↵", "Connect")
                    if selectedHostHasAlternateUsers {
                        hint("⌥↵", "Connect as…")
                    }
                    if selectedHostHasLocalForwards {
                        hint("⇧↵", "ssh -L")
                    }
                    if selectedHostHasRemoteForwards {
                        hint("⌃↵", "ssh -R")
                    }
                    if selectedHostHasVNC {
                        hint("⌘↵", "VNC")
                    }
                    hint("⌘E", "Edit")
                    hint("⌘I", "Copy IP")
                    hint("⌘R", "Refresh")
                    hint("⌘D", "Delete")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 600)
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            dismissUserPicker()
        }
        .onAppear { queryFocused = true }
        .onKeyPress(.downArrow) {
            if userPickerHost != nil {
                moveUserPicker(by: 1)
            } else {
                move(by: 1)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if userPickerHost != nil {
                moveUserPicker(by: -1)
            } else {
                move(by: -1)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if userPickerHost != nil {
                dismissUserPicker()
            } else {
                onClose()
            }
            return .handled
        }
        .onKeyPress(keys: [.return]) { press in
            guard userPickerHost == nil else {
                activateSelected()
                return .handled
            }
            let mods = press.modifiers
            if mods.contains(.option) {
                openUserPicker()
                return .handled
            }
            if mods.contains(.shift), let host = selectedHost, !host.localForwards.isEmpty {
                onConnectForwarding(host, nil, true, false)
                return .handled
            }
            if mods.contains(.control), let host = selectedHost, !host.remoteForwards.isEmpty {
                onConnectForwarding(host, nil, false, true)
                return .handled
            }
            if mods.contains(.command), let host = selectedHost, host.remoteApp != nil {
                onConnectVNC(host)
                return .handled
            }
            activateSelected()
            return .handled
        }
        .onKeyPress(keys: ["e"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if let host = selectedHost { onEdit(host) }
            return .handled
        }
        .onKeyPress(keys: ["c"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if let host = selectedHost { onCopy(host) }
            return .handled
        }
        .onKeyPress(keys: ["i"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if let host = selectedHost { onCopyIP(host) }
            return .handled
        }
        .onKeyPress(keys: ["r"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            refreshSelected()
            return .handled
        }
        .onKeyPress(keys: ["d"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if let host = selectedHost { onDelete(host) }
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .palettePerformRefresh)) { _ in
            refreshSelected()
        }
        .onKeyPress(keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]) { press in
            guard press.modifiers.contains(.command),
                  let digit = press.characters.first.flatMap({ Int(String($0)) }),
                  digit >= 1, digit <= 9 else { return .ignored }
            let index = digit - 1
            if let host = userPickerHost {
                let entries = userPickerEntries(for: host)
                guard entries.indices.contains(index) else { return .handled }
                onConnect(host, entries[index].user)
                dismissUserPicker()
            } else {
                guard results.indices.contains(index) else { return .handled }
                onConnect(results[index], nil)
            }
            return .handled
        }
    }

    private func row(for host: SSHHost, index: Int) -> some View {
        let alias = host.aliases.first ?? host.title
        let isSelected = index == selectedIndex
        let isFav = favorites.isFavorite(alias)
        let subtitle = subtitleString(for: host)
        let reachStatus = reachStatus(for: host)
        let isJumpHost = !Set(host.aliases).isDisjoint(with: jumpHostAliases)

        return HStack(spacing: 10) {
            Group {
                if let reachStatus {
                    ReachabilityDot(status: reachStatus, size: 8)
                } else {
                    Color.clear.frame(width: 8, height: 8)
                }
            }
            .frame(width: 10)
            Image(systemName: isFav ? "star.fill" : "terminal")
                .foregroundStyle(isFav ? Color.yellow : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(host.title)
                        .font(.body)
                        .lineLimit(1)
                    if reachCache.keyState(for: host).isChanged {
                        HostKeyWarningGlyph(size: 11)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let pj = host.proxyJump?.trimmingCharacters(in: .whitespaces), !pj.isEmpty {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .help("Connects through \(pj)")
            }
            if host.hasForwards {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .help("Port forwards — ⇧↵ local (-L), ⌃↵ reverse (-R)")
            }
            if isJumpHost {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .help("Used as a jump host by other entries")
            }
            let altUsers = host.alternateUsers.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if !altUsers.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(altUsers.count + 1)")
                        .font(.caption2)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                .help("Alt users: \(altUsers.joined(separator: ", ")) — ⌥↵ to pick")
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            }
            if isSelected {
                Image(systemName: "return")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .onTapGesture { onConnect(host, nil) }
        .contextMenu {
            let primary = host.user?.trimmingCharacters(in: .whitespaces) ?? ""
            Button(primary.isEmpty ? "Connect (default user)" : "Connect as \(primary)") {
                onConnect(host, nil)
            }
            let altUsers = host.alternateUsers.filter { !$0.isEmpty }
            if !altUsers.isEmpty {
                Divider()
                ForEach(altUsers, id: \.self) { user in
                    Button("Connect as \(user)") { onConnect(host, user) }
                }
            }
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
        }
    }

    private var jumpHostAliases: Set<String> {
        SSHHost.jumpHostAliases(in: hosts)
    }

    private var selectedHost: SSHHost? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    private var selectedHostHasAlternateUsers: Bool {
        guard let host = selectedHost else { return false }
        return host.alternateUsers.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var selectedHostHasLocalForwards: Bool {
        selectedHost.map { !$0.localForwards.isEmpty } ?? false
    }

    private var selectedHostHasRemoteForwards: Bool {
        selectedHost.map { !$0.remoteForwards.isEmpty } ?? false
    }

    private var selectedHostHasVNC: Bool {
        selectedHost.map { $0.remoteApp != nil } ?? false
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = max(0, min(results.count - 1, next))
    }

    private func activateSelected() {
        if let host = userPickerHost {
            let entries = userPickerEntries(for: host)
            guard entries.indices.contains(userPickerIndex) else { return }
            onConnect(host, entries[userPickerIndex].user)
            dismissUserPicker()
            return
        }
        if let host = selectedHost { onConnect(host, nil) }
    }

    private func openUserPicker() {
        guard let host = selectedHost else { return }
        let alts = host.alternateUsers.filter { !$0.isEmpty }
        guard !alts.isEmpty else { return }
        userPickerHost = host
        userPickerIndex = 0
    }

    private func dismissUserPicker() {
        guard userPickerHost != nil else { return }
        userPickerHost = nil
        userPickerIndex = 0
    }

    private func moveUserPicker(by delta: Int) {
        guard let host = userPickerHost else { return }
        let entries = userPickerEntries(for: host)
        guard !entries.isEmpty else { return }
        userPickerIndex = max(0, min(entries.count - 1, userPickerIndex + delta))
    }

    private func userPickerEntries(for host: SSHHost) -> [(label: String, user: String?, isDefault: Bool)] {
        var entries: [(String, String?, Bool)] = []
        let primary = host.user?.trimmingCharacters(in: .whitespaces) ?? ""
        entries.append((primary.isEmpty ? "default user" : primary, nil, true))
        for u in host.alternateUsers.map({ $0.trimmingCharacters(in: .whitespaces) }) where !u.isEmpty {
            entries.append((u, u, false))
        }
        return entries
    }

    @ViewBuilder
    private func userPickerContent(for host: SSHHost) -> some View {
        let entries = userPickerEntries(for: host)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connect as")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(host.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let isSelected = index == userPickerIndex
                HStack(spacing: 10) {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(entry.label)
                        .font(.body)
                    if entry.isDefault {
                        Text("default")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                    if index < 9 {
                        Text("⌘\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if isSelected {
                        Image(systemName: "return")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .onTapGesture {
                    onConnect(host, entry.user)
                    dismissUserPicker()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func reachStatus(for host: SSHHost) -> ReachStatus? {
        guard let key = ReachabilityCache.cacheKey(for: host) else { return nil }
        return reachCache.status(for: key)
    }

    private func refreshSelected() {
        guard let host = selectedHost,
              let probe = ReachabilityCache.probeTarget(for: host),
              let key = ReachabilityCache.cacheKey(for: host) else { return }
        reachCache.set(.checking, for: key)
        reachCache.setKeyStatus(.unchecked, for: key)
        Task {
            let success = await Reachability.probe(host: probe.target, port: probe.port)
            await MainActor.run {
                reachCache.set(success ? .reachable : .unreachable, for: key)
            }
            if success {
                await reachCache.runKeyCheck(for: host)
            }
        }
    }

    private func subtitleString(for host: SSHHost) -> String? {
        var parts: [String] = []
        if let user = host.user, !user.isEmpty, let hostName = host.hostName, !hostName.isEmpty {
            parts.append("\(user)@\(hostName)")
        } else if let hostName = host.hostName, !hostName.isEmpty {
            parts.append(hostName)
        } else if let user = host.user, !user.isEmpty {
            parts.append(user)
        }
        if let port = host.port, port != 22 {
            parts.append(":\(port)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var results: [SSHHost] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let scored: [(host: SSHHost, score: Int)]
        if trimmed.isEmpty {
            scored = hosts.map { ($0, 0) }
        } else {
            scored = hosts.compactMap { host in
                let s = score(host: host, query: trimmed)
                return s > 0 ? (host, s) : nil
            }
        }

        let ranked = scored.sorted { a, b in
            let aFav = favorites.isFavorite(a.host.aliases.first ?? "")
            let bFav = favorites.isFavorite(b.host.aliases.first ?? "")
            let aScore = a.score + (aFav ? 50 : 0)
            let bScore = b.score + (bFav ? 50 : 0)
            if aScore != bScore { return aScore > bScore }
            return a.host.title.localizedCaseInsensitiveCompare(b.host.title) == .orderedAscending
        }

        return Array(ranked.prefix(maxResults)).map(\.host)
    }

    private func score(host: SSHHost, query: String) -> Int {
        let tagName = host.aliases.first
            .flatMap { tagsStore.tag(for: $0) }
            .map { tagsStore.displayName(for: $0) }
        return HostSearchScorer.score(host: host, query: query, tagName: tagName)
    }
}
