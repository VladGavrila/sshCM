import SwiftUI
import AppKit

struct MenuBarMenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Command Palette") {
            CommandPaletteController.shared.toggle()
        }
        .keyboardShortcut("k", modifiers: [.command, .option])

        Button("Show Main Window") {
            showMainWindow()
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Quit sshCM") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let existing = NSApp.windows.first { window in
            window.canBecomeMain && !(window is CommandPalettePanel)
        }
        if let existing {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
