import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct sshCMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ConfigStore()
    @State private var favorites = FavoritesStore()
    @State private var updater = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(favorites)
                .environment(updater)
                .onAppear { store.load() }
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
                Button("Reload Config") { store.load() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(updater)
        }
    }
}
