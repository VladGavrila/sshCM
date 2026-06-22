import Foundation
import Observation

@MainActor
@Observable
final class ConfigStore {
    var file = SSHConfigFile()
    var loadError: String?

    static let defaultConfigURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh/config")

    private let fileURL: URL

    // The default is evaluated at call-site so it must not reference the
    // @MainActor-isolated static directly; instead it is resolved in the body.
    init(configURL: URL? = nil) {
        self.fileURL = configURL ?? ConfigStore.defaultConfigURL
    }

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
            let linuxAppConfigured = !(UserDefaults.standard.string(forKey: AppStorageKey.defaultLinuxVNCAppPath.rawValue) ?? "").isEmpty
            parsed.migrateLegacyOSMarkers(linuxAppPathConfigured: linuxAppConfigured)
            file = parsed
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// - Parameter publish: when `false`, the `/etc/hosts` sync is skipped so a
    ///   caller applying several changes in a row (e.g. import) can batch them
    ///   into a single admin prompt by calling `publishHostsIfEnabled()` once at
    ///   the end. The config file itself is still persisted on every call.
    func add(_ host: SSHHost, publish: Bool = true) {
        file.append(host: host)
        persist()
        if publish { publishHostsIfEnabled() }
    }

    func remove(id: UUID, publish: Bool = true) {
        file.remove(id: id)
        persist()
        if publish { publishHostsIfEnabled() }
    }

    func update(_ host: SSHHost, publish: Bool = true) {
        file.update(host)
        persist()
        if publish { publishHostsIfEnabled() }
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
