import Foundation
import Observation

@MainActor
@Observable
final class ConfigStore {
    var file = SSHConfigFile()
    var loadError: String?
    private(set) var lastDiskData: Data?

    static let defaultConfigURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh/config")

    private let fileURL: URL
    private let watcher = ConfigFileWatcher()

    var configURL: URL { fileURL }

    // The default is evaluated at call-site so it must not reference the
    // @MainActor-isolated static directly; instead it is resolved in the body.
    init(configURL: URL? = nil) {
        self.fileURL = configURL ?? ConfigStore.defaultConfigURL
    }

    func load() {
        loadError = nil
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                // A dangling symlink (the synced target is unmounted/evicted)
                // must not reset hosts to zero — that's a transient
                // unavailability, not "no config". A genuinely absent config
                // (no file, no link) still resets to empty.
                if ConfigLocation.linkedTarget(configURL: fileURL) != nil {
                    loadError = "Synced config isn't available right now. It will reload automatically once it's reachable again."
                    if let target = ConfigLocation.linkedTarget(configURL: fileURL) {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: target)
                    }
                    return
                }
                file = SSHConfigFile()
                lastDiskData = nil
                return
            }
            let data = try Data(contentsOf: fileURL)
            apply(data)
            lastDiskData = data
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func apply(_ data: Data) {
        let text = String(data: data, encoding: .utf8) ?? ""
        var parsed = SSHConfigParser.parse(text)
        parsed.preserveIDs(from: file)
        let linuxAppConfigured = !(UserDefaults.standard.string(forKey: AppStorageKey.defaultLinuxVNCAppPath.rawValue) ?? "").isEmpty
        parsed.migrateLegacyOSMarkers(linuxAppPathConfigured: linuxAppConfigured)
        file = parsed
    }

    /// Re-reads the watched target and applies it only if the bytes actually
    /// changed — this neutralizes the watcher firing on our own `persist()`
    /// writes. Called by the watcher's `onChange`.
    func reloadIfChangedOnDisk() {
        guard let target = try? ConfigLocation.resolveTarget(of: fileURL),
              let data = try? Data(contentsOf: target) else {
            load()
            return
        }
        guard data != lastDiskData else { return }
        apply(data)
        lastDiskData = data
        loadError = nil
    }

    /// Arms the file watcher on the resolved config target. Safe to call
    /// repeatedly (idempotent on an unchanged target).
    func startWatching() {
        guard let target = try? ConfigLocation.resolveTarget(of: fileURL) else { return }
        watcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.reloadIfChangedOnDisk()
            }
        }
        watcher.watch(target: target)
    }

    /// Called after Settings adopts/reverts the sync target: reloads content
    /// from the new location and re-arms the watcher on it.
    func configLocationDidChange() {
        load()
        startWatching()
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

    /// Applies `transform` to every host, persisting (and publishing to
    /// `/etc/hosts`) once at the end if anything changed. Used for batched
    /// multi-host rewrites (e.g. renaming/deleting a zone) so N member hosts
    /// don't trigger N separate persists.
    func updateAll(_ transform: (inout SSHHost) -> Void, publish: Bool = true) {
        var changed = false
        for host in file.hosts {
            var updated = host
            transform(&updated)
            if updated != host {
                file.update(updated)
                changed = true
            }
        }
        guard changed else { return }
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
            let data = Data(file.serialize().utf8)
            let fm = FileManager.default

            // Write through a symlinked config to its resolved target, not
            // the link node itself — `replaceItemAt` on a symlink path
            // replaces the *link*, silently breaking sync on the first save.
            let target = try ConfigLocation.writeTarget(for: fileURL)

            // Stage into a sibling temp file created 0600 up front, then swap it
            // in atomically. `Data.write(.atomic)` would create its own temp at
            // the process umask (typically 0644), leaving the config's bytes
            // briefly world-readable before `setAttributes` tightens them.
            let dir = target.deletingLastPathComponent()
            let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).sshcm-\(UUID().uuidString)")
            guard fm.createFile(atPath: tmp.path, contents: data,
                                attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: target)
            }
            // Re-assert 0600: replaceItemAt preserves the *original* file's
            // permissions, which may have been looser than we want.
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            lastDiskData = data
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
