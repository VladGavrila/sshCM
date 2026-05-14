import AppKit
import Carbon.HIToolbox
import Foundation

enum KeyShortcut {
    static let defaultKeyCode: Int = kVK_ANSI_K
    static let defaultModifiers: Int = Int(NSEvent.ModifierFlags.option.rawValue)
    static let defaultDisplay: String = "K"

    enum StorageKey {
        static let enabled = "globalHotKeyEnabled"
        static let keyCode = "globalHotKeyKeyCode"
        static let modifiers = "globalHotKeyModifiers"
        static let display = "globalHotKeyDisplay"
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
}

extension Notification.Name {
    static let openCommandPalette = Notification.Name("sshCM.openCommandPalette")
}
