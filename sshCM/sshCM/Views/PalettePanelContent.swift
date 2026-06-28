import SwiftUI

struct PalettePanelContent: View {
    let onConnect: (SSHHost, String?) -> Void
    let onConnectForwarding: (SSHHost, String?, Bool, Bool) -> Void
    let onConnectVNC: (SSHHost) -> Void
    let onConnectSMB: (SSHHost) -> Void
    let onEdit: (SSHHost) -> Void
    let onCopy: (SSHHost) -> Void
    let onCopyIP: (SSHHost) -> Void
    let onDelete: (SSHHost) -> Void
    let onClose: () -> Void

    @Environment(ConfigStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TagsStore.self) private var tagsStore

    var body: some View {
        CommandPaletteView(
            hosts: sortedHosts,
            onConnect: onConnect,
            onConnectForwarding: onConnectForwarding,
            onConnectVNC: onConnectVNC,
            onConnectSMB: onConnectSMB,
            onEdit: onEdit,
            onCopy: onCopy,
            onCopyIP: onCopyIP,
            onDelete: onDelete,
            onClose: onClose
        )
    }

    private var sortedHosts: [SSHHost] {
        let untaggedRank = HostTag.allCases.count
        return store.file.hosts.sorted { a, b in
            let aAlias = a.aliases.first ?? ""
            let bAlias = b.aliases.first ?? ""

            let aFav = favorites.isFavorite(aAlias)
            let bFav = favorites.isFavorite(bAlias)
            if aFav != bFav { return aFav }

            let aTagRank = tagsStore.tag(for: aAlias).map { tagsStore.rank(for: $0) } ?? untaggedRank
            let bTagRank = tagsStore.tag(for: bAlias).map { tagsStore.rank(for: $0) } ?? untaggedRank
            if aTagRank != bTagRank { return aTagRank < bTagRank }

            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
