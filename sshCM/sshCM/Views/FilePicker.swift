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

    /// Open panel for choosing a config-sync target: either an existing file
    /// (adopt its content) or a folder (a new `ssh_config` file is created
    /// inside it). `NSOpenPanel` can't name a file that doesn't exist yet, and
    /// `NSSavePanel`'s "Replace?" prompt would falsely imply this overwrites
    /// the synced file, when adoption is actually the opposite. Returns `nil`
    /// if cancelled.
    @MainActor
    static func pickConfigSyncTarget() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.title = "Choose Synced Config File"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return url.appendingPathComponent("ssh_config")
        }
        return url
    }
}
