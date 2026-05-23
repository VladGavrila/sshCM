import SwiftUI

struct HostRowView: View {
    let host: SSHHost
    let isJumpHost: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void
    let onConnectAs: (String) -> Void

    @Environment(FavoritesStore.self) private var favorites
    @Environment(TagsStore.self) private var tagsStore
    @Environment(ReachabilityCache.self) private var reachCache

    private var reachStatus: ReachStatus {
        guard let cacheKey = ReachabilityCache.cacheKey(for: host) else {
            return .unreachable
        }
        return reachCache.status(for: cacheKey) ?? .checking
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
        if altUsers.isEmpty {
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
                Divider()
                ForEach(altUsers, id: \.self) { user in
                    Button("Connect as \(user)") { onConnectAs(user) }
                }
            } label: {
                Image(systemName: "terminal")
            } primaryAction: {
                onConnect()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Connect via SSH — hold to pick a user")
        }
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
