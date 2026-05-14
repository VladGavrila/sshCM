import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppPresentation.current.activationPolicy)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true
    }
}

@main
struct sshCMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ConfigStore()
    @State private var favorites = FavoritesStore()
    @State private var tags = TagsStore()
    @State private var reachCache = ReachabilityCache()
    @State private var updater = UpdateChecker()
    @State private var paletteBridge = PaletteBridge()
    @State private var hotKey = GlobalHotKey()

    @AppStorage(KeyShortcut.StorageKey.enabled) private var hotKeyEnabled: Bool = true
    @AppStorage(KeyShortcut.StorageKey.keyCode) private var hotKeyCode: Int = KeyShortcut.defaultKeyCode
    @AppStorage(KeyShortcut.StorageKey.modifiers) private var hotKeyModifiers: Int = KeyShortcut.defaultModifiers
    @AppStorage(AppPresentation.storageKey) private var presentationRaw: String = AppPresentation.dock.rawValue

    private var presentation: AppPresentation {
        AppPresentation(rawValue: presentationRaw) ?? .dock
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { (AppPresentation(rawValue: presentationRaw) ?? .dock) == .menuBar },
            set: { presentationRaw = ($0 ? AppPresentation.menuBar : AppPresentation.dock).rawValue }
        )
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
                .environment(favorites)
                .environment(tags)
                .environment(reachCache)
                .environment(updater)
                .environment(paletteBridge)
                .onAppear {
                    store.load()
                    configurePalette()
                    hotKey.onTrigger = {
                        CommandPaletteController.shared.toggle()
                    }
                    applyHotKey()
                }
                .onChange(of: hotKeyEnabled) { _, _ in applyHotKey() }
                .onChange(of: hotKeyCode) { _, _ in applyHotKey() }
                .onChange(of: hotKeyModifiers) { _, _ in applyHotKey() }
                .task { updater.checkAtLaunchIfNeeded() }
                .frame(minWidth: 990, maxWidth: 1320, minHeight: 390)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
            }
            CommandGroup(after: .newItem) {
                Button("Reload Config") {
                    reachCache.clear()
                    store.load()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(updater)
                .environment(tags)
        }

        MenuBarExtra("sshCM", systemImage: "server.rack", isInserted: menuBarInserted) {
            MenuBarMenuContent()
        }
        .menuBarExtraStyle(.menu)
    }

    private func configurePalette() {
        let bridge = paletteBridge
        CommandPaletteController.shared.configure(.init(
            store: store,
            favorites: favorites,
            tagsStore: tags,
            onConnect: { host in
                guard let alias = host.aliases.first, !alias.isEmpty else { return }
                let path = UserDefaults.standard.string(forKey: "defaultTerminalAppPath")
                    ?? TerminalLauncher.defaultTerminalAppPath
                do {
                    try TerminalLauncher.launchSSH(toAlias: alias, terminalAppPath: path)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could not open terminal"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            },
            onEdit: { host in
                Self.surfaceMainWindow()
                bridge.pendingEdit = host
            },
            onCopy: { host in
                guard let alias = host.aliases.first, !alias.isEmpty else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("ssh \(alias)", forType: .string)
            },
            onDelete: { host in
                Self.surfaceMainWindow()
                bridge.pendingDelete = host
            }
        ))
    }

    @MainActor
    private static func surfaceMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindow = NSApp.windows.first { window in
            window.canBecomeMain && !(window is CommandPalettePanel)
        }
        if let mainWindow {
            if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func applyHotKey() {
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(hotKeyModifiers))
        hotKey.reconfigure(
            enabled: hotKeyEnabled,
            keyCode: UInt32(hotKeyCode),
            modifiers: KeyShortcut.carbonModifiers(from: nsFlags)
        )
    }
}
