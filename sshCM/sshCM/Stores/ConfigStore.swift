import Foundation
import Observation

@MainActor
@Observable
final class ConfigStore {
    var file = SSHConfigFile()
    var loadError: String?

    private let fileURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh/config")

    func load() {
        loadError = nil
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                file = SSHConfigFile()
                return
            }
            let data = try Data(contentsOf: fileURL)
            let text = String(data: data, encoding: .utf8) ?? ""
            var parsed = SSHConfigParser.parse(text)
            parsed.preserveIDs(from: file)
            file = parsed
        } catch {
            loadError = error.localizedDescription
        }
    }

    func add(_ host: SSHHost) {
        file.append(host: host)
        persist()
        publishHostsIfEnabled()
    }

    func remove(id: UUID) {
        file.remove(id: id)
        persist()
        publishHostsIfEnabled()
    }

    func update(_ host: SSHHost) {
        file.update(host)
        persist()
        publishHostsIfEnabled()
    }

    /// Re-syncs the `/etc/hosts` managed block after a host change, when the
    /// feature is enabled. No-op (and no admin prompt) unless the block actually
    /// changes.
    func publishHostsIfEnabled() {
        guard HostsFilePublisher.isEnabled() else { return }
        let hosts = file.hosts
        Task {
            let result = await HostsFilePublisher.sync(hosts: hosts)
            if case .failed(let message) = result {
                loadError = "Could not update /etc/hosts: \(message)"
            }
        }
    }

    private func persist() {
        do {
            try ensureSSHDirectory()
            let text = file.serialize()
            try text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            loadError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func ensureSSHDirectory() throws {
        let dir = fileURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }
}
