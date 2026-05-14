import AppKit
import Foundation

enum AppPresentation: String, CaseIterable, Identifiable {
    case dock
    case menuBar = "menubar"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dock: return "Dock icon"
        case .menuBar: return "Menu bar icon"
        }
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .dock: return .regular
        case .menuBar: return .accessory
        }
    }

    static let storageKey = "appPresentation"

    static var current: AppPresentation {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppPresentation.dock.rawValue
        return AppPresentation(rawValue: raw) ?? .dock
    }
}
