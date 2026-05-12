import SwiftUI

struct CommandPaletteView: View {
    let hosts: [SSHHost]
    let onConnect: (SSHHost) -> Void
    let onEdit: (SSHHost) -> Void
    let onCopy: (SSHHost) -> Void
    let onDelete: (SSHHost) -> Void
    let onClose: () -> Void

    @Environment(FavoritesStore.self) private var favorites
    @Environment(TagsStore.self) private var tagsStore

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var queryFocused: Bool

    private let maxResults = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search hosts…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($queryFocused)
                    .onSubmit { activateSelected() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if results.isEmpty {
                Text(hosts.isEmpty ? "No hosts in ~/.ssh/config." : "No matches for \"\(query)\".")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, host in
                                row(for: host, index: index)
                                    .id(host.id)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { _, newValue in
                        if results.indices.contains(newValue) {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(results[newValue].id, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 16) {
                hint("↵", "Connect")
                hint("⌘E", "Edit")
                hint("⌘C", "Copy ssh")
                hint("⌘D", "Delete")
                Spacer()
                hint("Esc", "Close")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 560)
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onAppear { queryFocused = true }
        .onKeyPress(.downArrow) {
            move(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(by: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
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
        .onKeyPress(keys: ["d"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if let host = selectedHost { onDelete(host) }
            return .handled
        }
    }

    private func row(for host: SSHHost, index: Int) -> some View {
        let alias = host.aliases.first ?? host.title
        let isSelected = index == selectedIndex
        let isFav = favorites.isFavorite(alias)
        let subtitle = subtitleString(for: host)

        return HStack(spacing: 10) {
            Image(systemName: isFav ? "star.fill" : "terminal")
                .foregroundStyle(isFav ? Color.yellow : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.title)
                    .font(.body)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "return")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .onTapGesture { onConnect(host) }
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

    private var selectedHost: SSHHost? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = max(0, min(results.count - 1, next))
    }

    private func activateSelected() {
        if let host = selectedHost { onConnect(host) }
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
        let q = query.lowercased()
        let alias = (host.aliases.first ?? "").lowercased()

        if !alias.isEmpty {
            if alias == q { return 1000 }
            if alias.hasPrefix(q) { return 500 + max(0, 20 - (alias.count - q.count)) }
            if alias.contains(q) { return 100 }
        }

        let tagName = host.aliases.first
            .flatMap { tagsStore.tag(for: $0) }
            .map { tagsStore.displayName(for: $0) }
        let others: [String?] = [
            host.title, host.hostName, host.user, host.identityFile, host.proxyJump,
            host.port.map(String.init), tagName
        ]
        for value in others.compactMap({ $0?.lowercased() }) where !value.isEmpty {
            if value.contains(q) { return 10 }
        }
        return 0
    }
}
