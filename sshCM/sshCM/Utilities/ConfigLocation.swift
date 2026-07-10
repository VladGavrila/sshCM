import Foundation

/// Manages `~/.ssh/config` as (optionally) a symlink to a file in a
/// user-chosen, sync-service-managed location — see AGENTS.md "Config File
/// Location" for the overall design. This namespace holds the pure,
/// Foundation-only planning/execution logic; `ConfigStore` and Settings UI
/// drive it.
///
/// Permission model: `ssh` only rejects a config file that is group- or
/// world-**writable**, so a sync client's default 0644 is perfectly usable.
/// The 0600 we chmod here/in `ConfigStore.persist()` is defense-in-depth,
/// applied best-effort — it also repairs looser modes a sync client may
/// recreate on every write.
enum ConfigLocation {
    enum LocationError: Error, LocalizedError {
        case symlinkCycle
        case targetIsConfig
        case notLinked
        case targetUnavailable

        var errorDescription: String? {
            switch self {
            case .symlinkCycle:
                return "That file is part of a symlink loop."
            case .targetIsConfig:
                return "That file already is (or points to) your SSH config."
            case .notLinked:
                return "The config file isn't currently a synced link."
            case .targetUnavailable:
                return "The synced location isn't available right now."
            }
        }
    }

    enum AdoptionPlan {
        /// Target already has content: it wins. `backupURL` is where the
        /// current `~/.ssh/config` (if a regular file) is preserved.
        case adoptTargetContent(backupURL: URL?)
        /// Target is missing/empty: local config content is moved into it.
        case seedTargetFromLocal(backupURL: URL?)
    }

    private static let maxHops = 8

    /// Follows a symlink chain manually (unlike `resolvingSymlinksInPath()`,
    /// this returns the final target even when it doesn't exist on disk).
    static func resolveTarget(of url: URL, maxHops: Int = ConfigLocation.maxHops) throws -> URL {
        var current = url
        var hops = 0
        while true {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            hops += 1
            if hops > maxHops { throw LocationError.symlinkCycle }
            if destination.hasPrefix("/") {
                current = URL(fileURLWithPath: destination)
            } else {
                current = current.deletingLastPathComponent().appendingPathComponent(destination)
            }
        }
    }

    /// Non-nil iff `configURL` is itself a symlink (uses `lstat`, not `stat`,
    /// so it doesn't follow the link).
    static func linkedTarget(configURL: URL) -> URL? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: configURL.path) else {
            return nil
        }
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }
        return configURL.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
    }

    /// Read-only decision about what choosing `chosen` as the sync target
    /// would do. Throws `.targetIsConfig` if `chosen` resolves to the same
    /// place as `configURL` (picking `~/.ssh/config` itself, or a link back
    /// to it).
    static func planAdoption(configURL: URL, chosen: URL, now: Date = Date()) throws -> AdoptionPlan {
        let resolvedChosen = (try? resolveTarget(of: chosen)) ?? chosen
        let resolvedConfig = (try? resolveTarget(of: configURL)) ?? configURL
        if resolvedChosen.standardizedFileURL.path == resolvedConfig.standardizedFileURL.path {
            throw LocationError.targetIsConfig
        }

        let backupURL = backupURLIfNeeded(configURL: configURL, now: now)

        let fm = FileManager.default
        if fm.fileExists(atPath: chosen.path) {
            let data = (try? Data(contentsOf: chosen)) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .adoptTargetContent(backupURL: backupURL)
            }
        }
        return .seedTargetFromLocal(backupURL: backupURL)
    }

    /// Computes the backup URL for `configURL`, or `nil` if `configURL` is
    /// already a symlink (nothing to lose by replacing it) or doesn't exist
    /// as a regular file at all.
    private static func backupURLIfNeeded(configURL: URL, now: Date) -> URL? {
        let fm = FileManager.default
        guard linkedTarget(configURL: configURL) == nil else { return nil }
        guard fm.fileExists(atPath: configURL.path) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "")
        let dir = configURL.deletingLastPathComponent()

        var candidate = dir.appendingPathComponent("config.backup-\(stamp)")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("config.backup-\(stamp)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    /// Executes an adoption plan: backs up the current config (if
    /// applicable), stages the target's content, and replaces
    /// `~/.ssh/config` with a symlink to `target`.
    static func execute(_ plan: AdoptionPlan, configURL: URL, target: URL) throws {
        let fm = FileManager.default

        switch plan {
        case .seedTargetFromLocal:
            let localData = (try? Data(contentsOf: configURL)) ?? Data()
            try stageFile(data: localData, at: target)
        case .adoptTargetContent:
            // Best-effort tighten; content is left as-is.
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }

        if let backupURL = backupURLFrom(plan) {
            if fm.fileExists(atPath: configURL.path) {
                try fm.moveItem(at: configURL, to: backupURL)
            }
        } else if linkedTarget(configURL: configURL) == nil, fm.fileExists(atPath: configURL.path) {
            // Regular file with no computed backup (shouldn't normally
            // happen since planAdoption always computes one for regular
            // files) — remove it so the symlink create below can proceed.
            try fm.removeItem(at: configURL)
        }

        try createSymlink(at: configURL, pointingTo: target)
    }

    private static func backupURLFrom(_ plan: AdoptionPlan) -> URL? {
        switch plan {
        case .adoptTargetContent(let backupURL), .seedTargetFromLocal(let backupURL):
            return backupURL
        }
    }

    /// Reverts `configURL` from a symlink back to a regular file containing
    /// the target's current bytes. The synced file itself is left untouched.
    static func revert(configURL: URL) throws {
        guard linkedTarget(configURL: configURL) != nil else {
            throw LocationError.notLinked
        }
        let target = try resolveTarget(of: configURL)
        let data = (try? Data(contentsOf: target)) ?? Data()

        let fm = FileManager.default
        let dir = configURL.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(configURL.lastPathComponent).sshcm-\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try posixRename(from: tmp, to: configURL)
    }

    /// Where `ConfigStore.persist()` should write: the resolved symlink
    /// target if `configURL` is linked, else `configURL` itself. Throws
    /// `.targetUnavailable` only when the target's parent directory is
    /// missing (e.g. an unmounted sync folder).
    static func writeTarget(for configURL: URL) throws -> URL {
        let target = (try? resolveTarget(of: configURL)) ?? configURL
        let dir = target.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw LocationError.targetUnavailable
        }
        return target
    }

    // MARK: - Low-level helpers

    /// Stages `data` into a sibling temp file (0600) and `rename(2)`s it over
    /// `target`. Creates an empty 0600 file if `data` is empty and `target`
    /// doesn't exist yet, so the eventual symlink is never dangling.
    private static func stageFile(data: Data, at target: URL) throws {
        let fm = FileManager.default
        let dir = target.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).sshcm-\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try posixRename(from: tmp, to: target)
    }

    /// Creates a symlink at `linkURL` pointing to `destination`, atomically
    /// replacing whatever node (file, symlink) currently sits there.
    private static func createSymlink(at linkURL: URL, pointingTo destination: URL) throws {
        let fm = FileManager.default
        let dir = linkURL.deletingLastPathComponent()
        let tmpLink = dir.appendingPathComponent(".\(linkURL.lastPathComponent).sshcm-link-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: tmpLink, withDestinationURL: destination)
        try posixRename(from: tmpLink, to: linkURL)
    }

    /// `rename(2)` atomically replaces the destination node, including when
    /// it's a symlink — unlike `FileManager.moveItem` (refuses an existing
    /// destination) or `replaceItemAt` (wrong for symlink nodes: it replaces
    /// the link itself rather than following it).
    private static func posixRename(from: URL, to: URL) throws {
        let result = from.path.withCString { fromPath in
            to.path.withCString { toPath in
                rename(fromPath, toPath)
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(errno))
            ])
        }
    }
}
