import Foundation
import Network

enum Reachability {
    static func probe(host: String, port: Int, timeout: TimeInterval = 5.0) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // `UInt16(port)` traps on an out-of-range port (e.g. a hand-edited
            // `Port 70000` in the config), which — since every host is probed on
            // launch — would crash the app at startup. Treat anything outside
            // 1…65535 as simply unreachable.
            guard let port16 = UInt16(exactly: port), let nwPort = NWEndpoint.Port(rawValue: port16) else {
                continuation.resume(returning: false)
                return
            }
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let state = ProbeState()
            @Sendable func finish(_ value: Bool) {
                guard state.markDone() else { return }
                conn.cancel()
                continuation.resume(returning: value)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }

    private final class ProbeState: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var done = false

        nonisolated func markDone() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}
