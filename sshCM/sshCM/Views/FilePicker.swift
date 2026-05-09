import AppKit
import Foundation

enum FilePicker {
    @MainActor
    static func pickFile(startingAt directoryURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = directoryURL ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        panel.prompt = "Select"
        panel.title = "Choose Identity File"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
