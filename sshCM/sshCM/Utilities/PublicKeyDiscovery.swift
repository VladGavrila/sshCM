import Foundation

enum PublicKeyDiscovery {
    static func discover() -> [URL] {
        let sshDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: sshDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "pub" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}
