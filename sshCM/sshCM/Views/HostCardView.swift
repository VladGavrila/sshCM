import SwiftUI

struct HostCardView: View {
    let host: SSHHost
    let isJumpHost: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void
    let onConnectAs: (String) -> Void
    /// Connect while applying the host's stored port forwards: `(includeLocal, includeRemote)`.
    let onConnectForwarding: (Bool, Bool) -> Void
    let onConnectVNC: () -> Void

    @Environment(FavoritesStore.self) private var favorites
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ReachabilityCache.self) private var reachCache
    @Environment(HostKeyBypassStore.self) private var bypassStore

    private var reachStatus: ReachStatus {
        guard let cacheKey = ReachabilityCache.cacheKey(for: host) else {
            return .unreachable
        }
        return reachCache.status(for: cacheKey) ?? .checking
    }

    private var hostKeyChanged: Bool {
        reachCache.keyState(for: host).isChanged
    }

    private var hostKeyBypassed: Bool {
        host.aliases.first.map { bypassStore.isBypassed($0) } ?? false
    }

    private var favoriteAlias: String? {
        host.aliases.first.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var isFavorite: Bool {
        favoriteAlias.map { favorites.isFavorite($0) } ?? false
    }

    private var hostTag: HostTag? {
        favoriteAlias.flatMap { tagsStore.tag(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            VStack(spacing: 6) {
                if let v = host.hostName, !v.isEmpty {
                    row(symbol: "network", value: v)
                }
                if let v = host.user, !v.isEmpty {
                    row(symbol: "person.fill", value: v)
                }
            }

            Divider()

            HStack(spacing: 12) {
                if let v = host.identityFile, !v.isEmpty {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                        .help(v)
                }
                if let v = host.proxyJump, !v.isEmpty {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.secondary)
                        .help(v)
                }
                if host.hasForwards {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                        .help(forwardsTooltip)
                }
                if let p = host.port, p != 22 {
                    Image(systemName: "number")
                        .foregroundStyle(.secondary)
                        .help(String(p))
                }
                if isJumpHost {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                        .help("Used as a jump host by other entries")
                }
                if hostKeyBypassed {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(.orange)
                        .help("Host key checking is bypassed for this host")
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove host")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit host")

                if host.os != nil {
                    Button(action: onConnectVNC) {
                        Image(systemName: "display")
                    }
                    .buttonStyle(.borderless)
                    .help("Connect via VNC")
                }

                connectButton
            }
        }
        .padding(14)
        .frame(minWidth: 300, maxWidth: 300, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(hostTag?.color ?? Color.clear, lineWidth: 2)
        )
        .padding(15)
    }

    @ViewBuilder
    private var connectButton: some View {
        let altUsers = host.alternateUsers.filter { !$0.isEmpty }
        if altUsers.isEmpty && !host.hasForwards {
            Button(action: onConnect) {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help("Connect via SSH")
        } else {
            Menu {
                let primary = host.user?.trimmingCharacters(in: .whitespaces) ?? ""
                Button(primary.isEmpty ? "Connect (default user)" : "Connect as \(primary)") {
                    onConnect()
                }
                forwardMenuItems
                if !altUsers.isEmpty {
                    Divider()
                    ForEach(altUsers, id: \.self) { user in
                        Button("Connect as \(user)") { onConnectAs(user) }
                    }
                }
            } label: {
                Image(systemName: "terminal")
            } primaryAction: {
                onConnect()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Connect via SSH — hold for forwards / users")
        }
    }

    @ViewBuilder
    private var forwardMenuItems: some View {
        if host.hasForwards {
            Divider()
            if !host.localForwards.isEmpty {
                Button("Connect with local forward (-L)") { onConnectForwarding(true, false) }
            }
            if !host.remoteForwards.isEmpty {
                Button("Connect with reverse forward (-R)") { onConnectForwarding(false, true) }
            }
            if !host.localForwards.isEmpty && !host.remoteForwards.isEmpty {
                Button("Connect with both forwards") { onConnectForwarding(true, true) }
            }
        }
    }

    private var forwardsTooltip: String {
        func describe(_ forwards: [PortForward], label: String) -> [String] {
            forwards.map { f in
                let detail = f.note.isEmpty ? f.spec : "\(f.note) — \(f.spec)"
                return "\(label) \(detail)"
            }
        }
        let lines = describe(host.localForwards, label: "-L") + describe(host.remoteForwards, label: "-R")
        return lines.joined(separator: "\n")
    }

    private var header: some View {
        HStack {
            reachIndicator
            Spacer()
            Text(host.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            if hostKeyChanged {
                HostKeyWarningGlyph()
            }
            Spacer()
            favoriteButton
        }
    }

    private var reachIndicator: some View {
        ReachabilityDot(status: reachStatus)
    }

    private var favoriteButton: some View {
        Button {
            if let alias = favoriteAlias {
                favorites.toggle(alias)
            }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.borderless)
        .disabled(favoriteAlias == nil)
        .help(isFavorite ? "Unpin from top" : "Pin to top")
    }

    private func row(symbol: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18, alignment: .center)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
                .help(value)
        }
    }
}
