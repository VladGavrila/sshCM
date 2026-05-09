import SwiftUI

@main
struct sshCMApp: App {
    @State private var store = ConfigStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onAppear { store.load() }
                .frame(minWidth: 990, maxWidth: 1320, minHeight: 390)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reload Config") { store.load() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
