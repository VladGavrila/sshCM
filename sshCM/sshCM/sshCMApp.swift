import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppPresentation.current.activationPolicy)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarStatusItem.shared.apply(AppPresentation.current)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Clicking the Dock icon (or relaunching) re-surfaces the hidden main window
        // instead of leaving the user with a running-but-windowless app.
        MainWindowCloseGuard.surfaceMainWindow()
        return true
    }
}

/// Intercepts the main window's close button (and ⌘W / "Close") so it hides the
/// window instead of destroying it. Closing previously quit the app, which fought
/// with the global command palette: the palette must activate the app to receive
/// keystrokes, and activating raises whatever main window exists. Hiding on close
/// lets the user tuck the window away so the palette can float alone over other
/// apps, while keeping a single window alive that the Dock icon, the main-window
/// hotkey, and the menu-bar item can re-surface. Other `NSWindowDelegate` messages
/// are forwarded to SwiftUI's own delegate so window behavior is otherwise unchanged.
final class MainWindowCloseGuard: NSObject, NSWindowDelegate {
    /// `NSWindow.delegate` is weak, so we must retain the guards ourselves.
    private static var guards: [MainWindowCloseGuard] = []

    private weak var forwardingDelegate: NSWindowDelegate?

    static func install(on window: NSWindow) {
        guard !(window.delegate is MainWindowCloseGuard) else { return }
        let guardDelegate = MainWindowCloseGuard()
        guardDelegate.forwardingDelegate = window.delegate
        window.delegate = guardDelegate
        guards.append(guardDelegate)
    }

    /// Installs the guard on every eligible main window (skips the command palette).
    static func installOnMainWindows() {
        for window in NSApp.windows where window.canBecomeMain && !(window is CommandPalettePanel) {
            install(on: window)
        }
    }

    @MainActor
    static func surfaceMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindow = NSApp.windows.first { window in
            window.canBecomeMain && !(window is CommandPalettePanel)
        }
        if let mainWindow {
            if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            MainWindowOpener.open?()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // Forward every other delegate message to SwiftUI's original delegate.
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwardingDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forwardingDelegate?.responds(to: aSelector) == true {
            return forwardingDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

@main
struct sshCMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ConfigStore()
    @State private var favorites = FavoritesStore()
    @State private var tags = TagsStore()
    @State private var reachCache = ReachabilityCache()
    @State private var bypassStore = HostKeyBypassStore()
    @State private var updater = UpdateChecker()
    @State private var paletteBridge = PaletteBridge()
    @State private var hotKey = GlobalHotKey()
    @State private var mainWindowHotKey = GlobalHotKey()

    @AppStorage(KeyShortcut.StorageKey.enabled) private var hotKeyEnabled: Bool = true
    @AppStorage(KeyShortcut.StorageKey.keyCode) private var hotKeyCode: Int = KeyShortcut.defaultKeyCode
    @AppStorage(KeyShortcut.StorageKey.modifiers) private var hotKeyModifiers: Int = KeyShortcut.defaultModifiers
    @AppStorage(KeyShortcut.Definition.mainWindow.enabledKey)
    private var mainWindowHotKeyEnabled: Bool = KeyShortcut.Definition.mainWindow.defaultEnabled
    @AppStorage(KeyShortcut.Definition.mainWindow.keyCodeKey)
    private var mainWindowHotKeyCode: Int = KeyShortcut.Definition.mainWindow.defaultKeyCode
    @AppStorage(KeyShortcut.Definition.mainWindow.modifiersKey)
    private var mainWindowHotKeyModifiers: Int = KeyShortcut.Definition.mainWindow.defaultModifiers
    @AppStorage(AppPresentation.storageKey) private var presentationRaw: String = AppPresentation.dock.rawValue

    private var presentation: AppPresentation {
        AppPresentation(rawValue: presentationRaw) ?? .dock
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
                .environment(favorites)
                .environment(tags)
                .environment(reachCache)
                .environment(bypassStore)
                .environment(updater)
                .environment(paletteBridge)
                .onAppear {
                    store.load()
                    configurePalette()
                    hotKey.onTrigger = {
                        CommandPaletteController.shared.toggle()
                    }
                    mainWindowHotKey.onTrigger = {
                        Self.surfaceMainWindow()
                    }
                    applyHotKey()
                    applyMainWindowHotKey()
                }
                .onChange(of: hotKeyEnabled) { _, _ in applyHotKey() }
                .onChange(of: hotKeyCode) { _, _ in applyHotKey() }
                .onChange(of: hotKeyModifiers) { _, _ in applyHotKey() }
                .onChange(of: mainWindowHotKeyEnabled) { _, _ in applyMainWindowHotKey() }
                .onChange(of: mainWindowHotKeyCode) { _, _ in applyMainWindowHotKey() }
                .onChange(of: mainWindowHotKeyModifiers) { _, _ in applyMainWindowHotKey() }
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
            CommandGroup(replacing: .newItem) {
                Button("Add Host…") {
                    Self.surfaceMainWindow()
                    paletteBridge.pendingAdd = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .newItem) {
                Button("Reload Config") {
                    if CommandPaletteController.shared.isPaletteVisible {
                        NotificationCenter.default.post(name: .palettePerformRefresh, object: nil)
                    } else {
                        reachCache.clear()
                        store.load()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(updater)
                .environment(tags)
        }
    }

    private func configurePalette() {
        let bridge = paletteBridge
        CommandPaletteController.shared.configure(.init(
            store: store,
            favorites: favorites,
            tagsStore: tags,
            reachCache: reachCache,
            onConnect: { [reachCache, bypassStore] host, user in
                let path = UserDefaults.standard.string(forKey: "defaultTerminalAppPath")
                    ?? TerminalLauncher.defaultTerminalAppPath
                do {
                    if let warning = try HostConnector.connect(
                        to: host,
                        as: user,
                        reachCache: reachCache,
                        bypassStore: bypassStore,
                        terminalAppPath: path
                    ) {
                        // The palette lives outside the SwiftUI window; surface the
                        // main window and let ContentView present the warning sheet.
                        Self.surfaceMainWindow()
                        bridge.pendingKeyWarning = warning
                    }
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could not open terminal"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            },
            onConnectForwarding: { [reachCache, bypassStore] host, user, local, remote in
                let path = UserDefaults.standard.string(forKey: "defaultTerminalAppPath")
                    ?? TerminalLauncher.defaultTerminalAppPath
                do {
                    if let warning = try HostConnector.connect(
                        to: host,
                        as: user,
                        localForwards: local ? host.localForwards.map(\.spec) : [],
                        remoteForwards: remote ? host.remoteForwards.map(\.spec) : [],
                        reachCache: reachCache,
                        bypassStore: bypassStore,
                        terminalAppPath: path
                    ) {
                        Self.surfaceMainWindow()
                        bridge.pendingKeyWarning = warning
                    }
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could not open terminal"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            },
            onConnectVNC: { host in
                guard let target = host.hostName?.trimmingCharacters(in: .whitespaces), !target.isEmpty else { return }
                let macOSAppPath = UserDefaults.standard.string(forKey: AppStorageKey.defaultMacOSVNCAppPath.rawValue)
                    ?? VNCLauncher.defaultMacOSVNCAppPath
                let linuxAppPath = UserDefaults.standard.string(forKey: AppStorageKey.defaultLinuxVNCAppPath.rawValue) ?? ""
                do {
                    try VNCLauncher.launch(
                        toHost: target,
                        port: host.vncPort ?? 5900,
                        os: host.os,
                        user: host.user,
                        macOSAppPath: macOSAppPath,
                        linuxAppPath: linuxAppPath
                    )
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could not open VNC client"
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
            onCopyIP: { host in
                let value = host.hostName?.trimmingCharacters(in: .whitespaces)
                    ?? host.aliases.first?.trimmingCharacters(in: .whitespaces)
                guard let value, !value.isEmpty else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(value, forType: .string)
            },
            onDelete: { host in
                Self.surfaceMainWindow()
                bridge.pendingDelete = host
            }
        ))
    }

    @MainActor
    private static func surfaceMainWindow() {
        MainWindowCloseGuard.surfaceMainWindow()
    }

    private func applyHotKey() {
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(hotKeyModifiers))
        hotKey.reconfigure(
            enabled: hotKeyEnabled,
            keyCode: UInt32(hotKeyCode),
            modifiers: KeyShortcut.carbonModifiers(from: nsFlags)
        )
        MenuBarStatusItem.shared.refreshMenu()
    }

    private func applyMainWindowHotKey() {
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(mainWindowHotKeyModifiers))
        mainWindowHotKey.reconfigure(
            enabled: mainWindowHotKeyEnabled,
            keyCode: UInt32(mainWindowHotKeyCode),
            modifiers: KeyShortcut.carbonModifiers(from: nsFlags)
        )
        MenuBarStatusItem.shared.refreshMenu()
    }
}
