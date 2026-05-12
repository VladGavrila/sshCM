import SwiftUI
import UniformTypeIdentifiers

enum HostTag: String, CaseIterable, Identifiable, Codable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red:    return Color(red: 0.92, green: 0.26, blue: 0.21)
        case .orange: return Color(red: 0.98, green: 0.55, blue: 0.16)
        case .yellow: return Color(red: 0.97, green: 0.82, blue: 0.18)
        case .green:  return Color(red: 0.30, green: 0.76, blue: 0.36)
        case .blue:   return Color(red: 0.18, green: 0.52, blue: 0.95)
        case .purple: return Color(red: 0.62, green: 0.32, blue: 0.83)
        case .gray:   return Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }

    var displayName: String {
        rawValue.capitalized
    }

    static var defaultOrder: [HostTag] {
        [.green, .yellow, .orange, .red, .blue, .purple, .gray]
    }
}

extension HostTag: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
