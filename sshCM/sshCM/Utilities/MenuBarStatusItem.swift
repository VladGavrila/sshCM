import AppKit

@MainActor
enum MainWindowOpener {
    static var open: (() -> Void)?
}

@MainActor
enum SettingsOpener {
    static var open: (() -> Void)?
}

@MainActor
enum UpdateCheckTrigger {
    static var trigger: (() -> Void)?
}

@MainActor
final class MenuBarStatusItem: NSObject {
    static let shared = MenuBarStatusItem()

    private var statusItem: NSStatusItem?

    private override init() { super.init() }

    func apply(_ presentation: AppPresentation) {
        switch presentation {
        case .dock:
            uninstall()
        case .menuBar:
            install()
        }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "sshCM")
            image?.isTemplate = true
            button.image = image
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func uninstall() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let palette = NSMenuItem(
            title: "Open Command Palette",
            action: #selector(openPalette(_:)),
            keyEquivalent: "k"
        )
        palette.keyEquivalentModifierMask = [.command, .option]
        palette.target = self
        menu.addItem(palette)

        let mainWindow = NSMenuItem(
            title: "Show Main Window",
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        mainWindow.target = self
        menu.addItem(mainWindow)

        menu.addItem(.separator())

        let checkUpdate = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdate.target = self
        menu.addItem(checkUpdate)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit sshCM",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        return menu
    }

    @objc private func openPalette(_ sender: Any?) {
        CommandPaletteController.shared.toggle()
    }

    @objc private func showMainWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let existing = NSApp.windows.first { window in
            window.canBecomeMain && !(window is CommandPalettePanel)
        }
        if let existing {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
            return
        }
        MainWindowOpener.open?()
    }

    @objc private func openSettings(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        SettingsOpener.open?()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        // Update results (sheet, alerts) are presented by ContentView, so ensure
        // a main window is visible before kicking off the check.
        NSApp.activate(ignoringOtherApps: true)
        let existing = NSApp.windows.first { window in
            window.canBecomeMain && !(window is CommandPalettePanel)
        }
        if let existing {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
        } else {
            MainWindowOpener.open?()
        }
        UpdateCheckTrigger.trigger?()
    }
}
