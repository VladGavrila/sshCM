import SwiftUI

struct PalettePanelContent: View {
    let initialZone: String?
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
    @Environment(TagsStore.self) private var tagsStore

    var body: some View {
        CommandPaletteView(
            hosts: sortedHosts,
            initialZone: initialZone,
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
            if a.isFavorite != b.isFavorite { return a.isFavorite }

            let aTagRank = a.tag.map { tagsStore.rank(for: $0) } ?? untaggedRank
            let bTagRank = b.tag.map { tagsStore.rank(for: $0) } ?? untaggedRank
            if aTagRank != bTagRank { return aTagRank < bTagRank }

            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
