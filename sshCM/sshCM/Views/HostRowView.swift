import SwiftUI

struct HostRowView: View {
    let host: SSHHost
    let isJumpHost: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void
    let onConnectAs: (String) -> Void
    /// Connect while applying the host's stored port forwards: `(includeLocal, includeRemote)`.
    let onConnectForwarding: (Bool, Bool) -> Void
    let onConnectVNC: () -> Void
    let onConnectSMB: () -> Void

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
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(hostTag?.color ?? Color.clear)
                .frame(width: 3, height: 22)

            ReachabilityDot(status: reachStatus)

            favoriteButton

            Text(host.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 140, alignment: .leading)

            if hostKeyChanged {
                HostKeyWarningGlyph()
            }

            HStack(spacing: 0) {
                if let u = host.user, !u.isEmpty {
                    Text(u).foregroundStyle(.secondary)
                    Text("@").foregroundStyle(.secondary)
                }
                if let h = host.hostName, !h.isEmpty {
                    Text(h).foregroundStyle(.primary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
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
                    HStack(spacing: 2) {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                        Text(String(p))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
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
            }

            HStack(spacing: 6) {
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

                if host.remoteApp != nil {
                    Button(action: onConnectVNC) {
                        Image(systemName: "display")
                    }
                    .buttonStyle(.borderless)
                    .help("Connect via VNC")
                }

                if host.allowsSMB {
                    Button(action: onConnectSMB) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                    }
                    .buttonStyle(.borderless)
                    .help("Connect via SMB")
                }

                connectButton
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var connectButton: some View {
        let altUsers = host.alternateUsers.filter { !$0.isEmpty }
        if altUsers.isEmpty && !host.hasForwards {
            Button(action: onConnect) {
                Image(systemName: "apple.terminal")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.borderless)
            .help("Connect via SSH")
        } else {
            // `Menu`'s built-in label rendering ignores SwiftUI-level sizing
            // modifiers on its icon (AppKit re-snapshots it for the menu
            // bezel at the symbol's own default size), so the visible icon
            // here is a separate, identically-styled overlay; the actual
            // `Menu` underneath is rendered invisible and only provides the
            // click target.
            ZStack {
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
                    Color.clear
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 14, height: 14)

                Image(systemName: "apple.terminal.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .allowsHitTesting(false)
            }
            .help("Connect via SSH - options")
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
}
