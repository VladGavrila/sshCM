import SwiftUI
import AppKit
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    @AppStorage(KeyShortcut.StorageKey.keyCode) private var keyCode: Int = KeyShortcut.defaultKeyCode
    @AppStorage(KeyShortcut.StorageKey.modifiers) private var modifiers: Int = KeyShortcut.defaultModifiers
    @AppStorage(KeyShortcut.StorageKey.display) private var display: String = KeyShortcut.defaultDisplay

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 90, alignment: .center)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                )

            Button(isRecording ? "Press keys…" : "Record") {
                if isRecording { stopRecording() } else { startRecording() }
            }

            Button("Reset") {
                stopRecording()
                keyCode = KeyShortcut.defaultKeyCode
                modifiers = KeyShortcut.defaultModifiers
                display = KeyShortcut.defaultDisplay
            }
        }
        .onDisappear { stopRecording() }
    }

    private var displayText: String {
        if isRecording { return "…" }
        return KeyShortcut.displayString(modifiers: modifiers, key: display)
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels
            if event.keyCode == kVK_Escape {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modifierOnly: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let activeMods = flags.intersection(modifierOnly)

            // Require at least one of cmd/opt/shift/ctrl to avoid swallowing plain letters
            guard !activeMods.isEmpty else {
                NSSound.beep()
                return nil
            }

            let chars = event.charactersIgnoringModifiers ?? ""
            let glyph: String
            if let special = Self.specialKeyName(for: Int(event.keyCode)) {
                glyph = special
            } else if !chars.isEmpty {
                glyph = chars.uppercased()
            } else {
                glyph = "Key \(event.keyCode)"
            }

            keyCode = Int(event.keyCode)
            modifiers = Int(activeMods.rawValue)
            display = glyph

            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private static func specialKeyName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }
}
