import SwiftUI

struct HostCardView: View {
    let host: SSHHost
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Text(host.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
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
                if let p = host.port {
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
