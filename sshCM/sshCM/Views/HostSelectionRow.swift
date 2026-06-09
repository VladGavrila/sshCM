import SwiftUI

/// A checkbox row used by the export and import sheets. It mirrors the main
/// window's list row (`HostRowView`) — same tag line, reachability dot, favorite
/// star, title and `user@hostName` detail — but prepends a checkbox and drops
/// the trailing icon cluster and action buttons, so the two surfaces share one
/// visual language.
///
/// `reachStatus` is optional: export passes the live status from the cache;
/// import passes `nil` (the hosts aren't probed) and a neutral hollow circle is
/// drawn in the same slot to keep the layout identical.
struct HostSelectionRow: View {
    let title: String
    let user: String?
    let hostName: String?
    let tag: HostTag?
    let reachStatus: ReachStatus?
    let favorite: Bool
    /// Optional trailing label, e.g. "already exists" on import.
    let badge: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()

            // Tag color stripe — identical to HostRowView.
            RoundedRectangle(cornerRadius: 2)
                .fill(tag?.color ?? Color.clear)
                .frame(width: 3, height: 22)

            // Reachability circle (or neutral placeholder when unprobed).
            if let reachStatus {
                ReachabilityDot(status: reachStatus)
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                    .help("Reachability not checked")
            }

            // Favorite star — only when favorited, but the slot is always
            // reserved so titles line up across rows.
            ZStack {
                Color.clear.frame(width: 14, height: 14)
                if favorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color.yellow)
                }
            }

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 140, alignment: .leading)

            HStack(spacing: 0) {
                if let user, !user.isEmpty {
                    Text(user).foregroundStyle(.secondary)
                    Text("@").foregroundStyle(.secondary)
                }
                if let hostName, !hostName.isEmpty {
                    Text(hostName).foregroundStyle(.primary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}
