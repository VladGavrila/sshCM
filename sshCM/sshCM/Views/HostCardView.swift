import SwiftUI

struct HostCardView: View {
    let host: SSHHost
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void

    enum ReachStatus {
        case checking, reachable, unreachable

        var color: Color {
            switch self {
            case .checking: return .orange
            case .reachable: return .green
            case .unreachable: return .red
            }
        }

        var help: String {
            switch self {
            case .checking: return "Checking reachability…"
            case .reachable: return "Host is reachable"
            case .unreachable: return "Host is not reachable"
            }
        }
    }

    @Environment(FavoritesStore.self) private var favorites

    @State private var reachStatus: ReachStatus = .checking
    @State private var pulsate: Bool = false

    private var favoriteAlias: String? {
        host.aliases.first.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var isFavorite: Bool {
        favoriteAlias.map { favorites.isFavorite($0) } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(reachStatus.color)
                    .frame(width: 10, height: 10)
                    .opacity(reachStatus == .checking ? (pulsate ? 0.3 : 1.0) : 1.0)
                    .animation(
                        reachStatus == .checking
                            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                            : .default,
                        value: pulsate
                    )
                    .onAppear { pulsate = reachStatus == .checking }
                    .onChange(of: reachStatus) { _, newValue in
                        pulsate = newValue == .checking
                    }
                    .help(reachStatus.help)
                Spacer()
                Text(host.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
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
                if let p = host.port, p != 22 {
                    Image(systemName: "number")
                        .foregroundStyle(.secondary)
                        .help(String(p))
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

                Button(action: onConnect) {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("Connect via SSH")
            }
        }
        .padding(14)
        .frame(minWidth: 300, maxWidth: 300, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .padding(15)
        .task(id: reachabilityKey) {
            await runReachabilityCheck()
        }
    }

    private var reachabilityKey: String {
        "\(host.hostName ?? host.aliases.first ?? "")|\(host.port ?? 22)"
    }

    private func runReachabilityCheck() async {
        let candidates = [host.hostName, host.aliases.first]
        let target = candidates
            .compactMap { $0?.trimmingCharacters(in: CharacterSet.whitespaces) }
            .first { !$0.isEmpty }
        guard let target else {
            reachStatus = .unreachable
            return
        }
        let port = host.port ?? 22

        reachStatus = .checking

        let success = await Reachability.probe(host: target, port: port)
        guard !Task.isCancelled else { return }
        reachStatus = success ? .reachable : .unreachable
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
