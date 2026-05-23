import AppKit
import Carbon.HIToolbox
import Foundation

enum KeyShortcut {
    static let defaultKeyCode: Int = Definition.palette.defaultKeyCode
    static let defaultModifiers: Int = Definition.palette.defaultModifiers
    static let defaultDisplay: String = Definition.palette.defaultDisplay

    enum StorageKey {
        static let enabled = Definition.palette.enabledKey
        static let keyCode = Definition.palette.keyCodeKey
        static let modifiers = Definition.palette.modifiersKey
        static let display = Definition.palette.displayKey
    }

    struct Definition {
        let enabledKey: String
        let keyCodeKey: String
        let modifiersKey: String
        let displayKey: String
        let defaultEnabled: Bool
        let defaultKeyCode: Int
        let defaultModifiers: Int
        let defaultDisplay: String

        static let palette = Definition(
            enabledKey: "globalHotKeyEnabled",
            keyCodeKey: "globalHotKeyKeyCode",
            modifiersKey: "globalHotKeyModifiers",
            displayKey: "globalHotKeyDisplay",
            defaultEnabled: true,
            defaultKeyCode: kVK_ANSI_K,
            defaultModifiers: Int(NSEvent.ModifierFlags.option.rawValue),
            defaultDisplay: "K"
        )

        static let mainWindow = Definition(
            enabledKey: "mainWindowHotKeyEnabled",
            keyCodeKey: "mainWindowHotKeyKeyCode",
            modifiersKey: "mainWindowHotKeyModifiers",
            displayKey: "mainWindowHotKeyDisplay",
            defaultEnabled: false,
            defaultKeyCode: kVK_ANSI_S,
            defaultModifiers: Int(NSEvent.ModifierFlags.option.rawValue),
            defaultDisplay: "S"
        )
    }

    static func carbonModifiers(from ns: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if ns.contains(.command) { m |= UInt32(cmdKey) }
        if ns.contains(.option) { m |= UInt32(optionKey) }
        if ns.contains(.shift) { m |= UInt32(shiftKey) }
        if ns.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func modifierGlyphs(_ ns: NSEvent.ModifierFlags) -> String {
        var s = ""
        if ns.contains(.control) { s += "⌃" }
        if ns.contains(.option) { s += "⌥" }
        if ns.contains(.shift) { s += "⇧" }
        if ns.contains(.command) { s += "⌘" }
        return s
    }

    static func displayString(modifiers: Int, key: String) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        let glyphs = modifierGlyphs(flags)
        let keyPart = key.isEmpty ? "?" : key.uppercased()
        if glyphs.isEmpty { return keyPart }
        return "\(glyphs) \(keyPart)"
    }

    static func menuKeyEquivalent(for definition: Definition) -> (key: String, mask: NSEvent.ModifierFlags)? {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: definition.enabledKey) as? Bool ?? definition.defaultEnabled
        guard enabled else { return nil }
        let modsRaw = defaults.object(forKey: definition.modifiersKey) as? Int ?? definition.defaultModifiers
        let display = defaults.string(forKey: definition.displayKey) ?? definition.defaultDisplay
        let mask = NSEvent.ModifierFlags(rawValue: UInt(modsRaw))
        // Only single alphanumeric characters translate cleanly into an NSMenuItem keyEquivalent.
        // Special keys (arrows, F-keys, Space, etc.) are skipped: the global hotkey still fires,
        // but the menu item is shown without a visible shortcut glyph.
        guard display.count == 1,
              let scalar = display.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar)
        else { return nil }
        return (display.lowercased(), mask)
    }
}

extension Notification.Name {
    static let openCommandPalette = Notification.Name("sshCM.openCommandPalette")
}
