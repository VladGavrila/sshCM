import Dispatch
import Foundation

/// Watches a single file path for changes and invokes `onChange` (on the main
/// queue) when its contents are modified. Used to auto-reload `ConfigStore`
/// when a synced config target changes on disk — see `ConfigLocation` and
/// AGENTS.md "Config File Location".
///
/// Atomic replaces — our own `persist()`, or a sync client's temp+rename —
/// surface as `.rename`/`.delete` on the watched inode rather than `.write`.
/// When that happens we cancel the source and retry opening the same path
/// every 0.5s for ~20s (the window a sync client needs to finish its
/// replace), re-arming a fresh source once the new inode appears. If retries
/// are exhausted we stop quietly: `ConfigStore.load()`'s dangling-target
/// error path covers the UX, and a relaunch, ⌘R, or a Settings action
/// re-arms the watcher.
///
/// Known limitation: re-pointing the `~/.ssh/config` symlink itself *outside*
/// the app isn't noticed until relaunch/⌘R/a Settings action, since we watch
/// the resolved target, not the link.
final class ConfigFileWatcher {
    var onChange: (@Sendable () -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var debounceWorkItem: DispatchWorkItem?
    private var retryWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue.global(qos: .utility)

    private static let retryInterval: TimeInterval = 0.5
    private static let retryTimeout: TimeInterval = 20

    /// Idempotent: re-watching the same path is a no-op; watching a new path
    /// tears down the old source first.
    func watch(target: URL) {
        if watchedPath == target.path, source != nil { return }
        stop()
        watchedPath = target.path
        arm(path: target.path)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        source?.cancel()
        source = nil
        watchedPath = nil
    }

    private func arm(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry(path: path, deadline: Date().addingTimeInterval(Self.retryTimeout))
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = newSource.data
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.handleNodeReplaced(path: path)
            } else {
                self.debounceFire()
            }
        }
        newSource.setCancelHandler {
            close(fd)
        }
        source = newSource
        newSource.resume()
    }

    private func handleNodeReplaced(path: String) {
        source?.cancel()
        source = nil
        scheduleRetry(path: path, deadline: Date().addingTimeInterval(Self.retryTimeout))
    }

    private func scheduleRetry(path: String, deadline: Date) {
        guard watchedPath == path else { return }
        guard Date() < deadline else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.watchedPath == path else { return }
            if FileManager.default.fileExists(atPath: path) {
                self.arm(path: path)
                self.debounceFire()
            } else {
                self.scheduleRetry(path: path, deadline: deadline)
            }
        }
        retryWorkItem = work
        queue.asyncAfter(deadline: .now() + Self.retryInterval, execute: work)
    }

    private func debounceFire() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let handler = self?.onChange else { return }
            DispatchQueue.main.async {
                handler()
            }
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
