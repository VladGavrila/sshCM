import Foundation
import Darwin

/// Platform (Darwin) helpers for the LAN host-discovery scan: figuring out which
/// subnet to prefill, and best-effort reverse-DNS naming of responders. These use
/// the C networking APIs (`getifaddrs`, `getnameinfo`) so they can't live in the
/// Foundation-only SPM package — verify by running, not by unit test. The pure
/// subnet math they feed is in `SubnetScan` (which is tested).
enum LocalNetwork {

    // MARK: - Interface discovery

    /// The active interface's IPv4 address and netmask, used to prefill the scan
    /// range. Enumerates `getifaddrs`, skips loopback / down / link-local
    /// interfaces, and prefers `en0` (the Mac's primary Ethernet/Wi-Fi) so a
    /// stray VPN `utun`, bridge, or virtualization interface doesn't win.
    static func primaryIPv4() -> (ip: String, netmask: String)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, head != nil else { return nil }
        defer { freeifaddrs(head) }

        var candidates: [(name: String, ip: String, mask: String)] = []
        var ptr = head
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0,
                  let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = cur.pointee.ifa_netmask,
                  let ipString = numericHost(addr),
                  let maskString = numericHost(mask) else { continue }
            // 169.254/16 is APIPA auto-assignment — it means "no real network",
            // not a subnet worth scanning.
            if ipString.hasPrefix("169.254.") { continue }
            candidates.append((String(cString: cur.pointee.ifa_name), ipString, maskString))
        }
        guard !candidates.isEmpty else { return nil }
        let chosen = candidates.first { $0.name == "en0" }
            ?? candidates.first { $0.name.hasPrefix("en") }
            ?? candidates[0]
        return (chosen.ip, chosen.mask)
    }

    /// Formats a `sockaddr` as its numeric host string (no DNS).
    private static func numericHost(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            sa, socklen_t(sa.pointee.sa_len),
            &buffer, socklen_t(buffer.count),
            nil, 0, NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Reverse DNS

    /// Best-effort reverse-DNS (PTR) lookup for a responder IP, used to suggest a
    /// friendly alias. The blocking resolver runs off the main actor and is raced
    /// against a short timeout so a slow or absent resolver never stalls the scan.
    /// Returns the first DNS label (e.g. `nas` from `nas.local`), or `nil` when
    /// there's no PTR record. The pattern mirrors `Reachability.probe`: an
    /// `NSLock`-guarded flag guarantees the continuation resumes exactly once, and
    /// the orphaned lookup task simply finishes and is discarded on timeout.
    static func reverseDNS(_ ip: String, timeout: TimeInterval = 2.0) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = OnceFlag()
            Task.detached(priority: .utility) {
                let name = blockingReverseDNS(ip)
                if once.markDone() { continuation.resume(returning: name) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if once.markDone() { continuation.resume(returning: nil) }
            }
        }
    }

    private static func blockingReverseDNS(_ ip: String) -> String? {
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &sa.sin_addr) == 1 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &sa) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                // NI_NAMEREQD: fail (rather than echo the numeric IP back) when
                // the host has no PTR record, so callers get a clean nil.
                getnameinfo(
                    saPtr, socklen_t(MemoryLayout<sockaddr_in>.size),
                    &buffer, socklen_t(buffer.count),
                    nil, 0, NI_NAMEREQD
                )
            }
        }
        guard result == 0 else { return nil }
        let full = String(cString: buffer)
        guard !full.isEmpty else { return nil }
        // Just the first label — strip any domain suffix / trailing dot.
        return full.split(separator: ".").first.map(String.init)
    }

    /// One-shot guard so a raced continuation resumes exactly once (mirrors
    /// `Reachability`'s `ProbeState`).
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func markDone() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}
