import AppKit
import SwiftUI

extension Notification.Name {
    static let palettePerformRefresh = Notification.Name("sshCM.palette.performRefresh")
}

@MainActor
final class CommandPaletteController: NSObject, NSWindowDelegate {
    static let shared = CommandPaletteController()

    var isPaletteVisible: Bool { panel?.isVisible ?? false }

    struct Configuration {
        var store: ConfigStore
        var favorites: FavoritesStore
        var tagsStore: TagsStore
        var reachCache: ReachabilityCache
        var onConnect: (SSHHost, String?) -> Void
        var onConnectForwarding: (SSHHost, String?, Bool, Bool) -> Void
        var onConnectVNC: (SSHHost) -> Void
        var onEdit: (SSHHost) -> Void
        var onCopy: (SSHHost) -> Void
        var onCopyIP: (SSHHost) -> Void
        var onDelete: (SSHHost) -> Void
    }

    private var panel: CommandPalettePanel?
    private var configuration: Configuration?

    private override init() { super.init() }

    func configure(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard let configuration else { return }
        teardownPanel()
        let panel = makePanel()

        let content = PalettePanelContent(
            onConnect: { [weak self] host, user in
                self?.close()
                configuration.onConnect(host, user)
            },
            onConnectForwarding: { [weak self] host, user, local, remote in
                self?.close()
                configuration.onConnectForwarding(host, user, local, remote)
            },
            onConnectVNC: { [weak self] host in
                self?.close()
                configuration.onConnectVNC(host)
            },
            onEdit: { [weak self] host in
                self?.close()
                configuration.onEdit(host)
            },
            onCopy: { host in
                configuration.onCopy(host)
            },
            onCopyIP: { host in
                configuration.onCopyIP(host)
            },
            onDelete: { [weak self] host in
                self?.close()
                configuration.onDelete(host)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        .environment(configuration.store)
        .environment(configuration.favorites)
        .environment(configuration.tagsStore)
        .environment(configuration.reachCache)

        let host = NSHostingView(rootView: AnyView(content))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        let size = host.fittingSize.width > 0 ? host.fittingSize : NSSize(width: 580, height: 380)
        panel.setContentSize(size)
        centerOnActiveScreen(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        teardownPanel()
    }

    private func teardownPanel() {
        guard let existing = panel else { return }
        existing.delegate = nil
        existing.makeFirstResponder(nil)
        existing.contentView = nil
        existing.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 380),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + visible.height * 0.7
        window.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
