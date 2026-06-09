import AppKit
import Foundation
import UniformTypeIdentifiers

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

    /// Save panel for writing the hosts export JSON. Returns `nil` if cancelled.
    @MainActor
    static func pickExportDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.title = "Export Hosts"
        panel.prompt = "Export"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Open panel for choosing a hosts export JSON to import. Returns `nil` if
    /// cancelled.
    @MainActor
    static func pickImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Hosts File"
        panel.prompt = "Import"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
