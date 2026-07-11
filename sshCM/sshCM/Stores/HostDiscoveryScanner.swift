import Foundation
import Observation

/// Drives a LAN sweep for hosts with SSH (port 22) open, backing the Discover
/// sheet. Fans `Reachability.probe` across a candidate IP list with a bounded
/// concurrency window, fills `results` as responders come in, and best-effort
/// reverse-DNS-names each one for a friendly alias suggestion.
///
/// It is not in the SPM package (it depends on `Reachability`/`LocalNetwork`),
/// so it's verified by running the app, not by unit test; the pure range math it
/// consumes lives in `SubnetScan`, which is tested.
@MainActor
@Observable
final class HostDiscoveryScanner {

    enum Phase: Equatable {
        case idle
        case scanning(probed: Int, total: Int)
        case done(found: Int)
    }

    /// One responder found during a scan. `alias` is user-editable in the sheet;
    /// `ipDerivedAlias` is the default we assigned, so reverse-DNS can refine the
    /// alias without clobbering a name the user has since typed.
    struct Discovered: Identifiable {
        let id = UUID()
        let ip: String
        var name: String?
        var alias: String
        let ipDerivedAlias: String
        var isSelected: Bool
        var alreadyInConfig: Bool
    }

    private(set) var phase: Phase = .idle
    var results: [Discovered] = []

    /// Concurrency cap for the sweep. A /24 is 254 probes; opening that many
    /// simultaneous `NWConnection`s is wasteful, so probe in a bounded window.
    private let maxInFlight = 48
    /// LAN round-trips are sub-millisecond, so a non-responder needn't wait the
    /// 5s reachability default — 1s keeps a full /24 sweep to a few seconds.
    private let probeTimeout: TimeInterval = 1.0

    /// Aliases already claimed (existing config + rows added so far), so
    /// suggested aliases stay unique. Mutated only on the main actor.
    private var takenAliases: Set<String> = []

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    /// Scans `candidates` for open port 22, appending responders to `results` as
    /// they're found. `existingHostNames` are IPs already in the config (so a
    /// responder can be flagged and pre-deselected); `existingAliases` seeds
    /// alias de-duplication. Honors cancellation — closing the sheet cancels the
    /// enclosing task, which propagates to every in-flight probe.
    func scan(candidates: [String], existingHostNames: Set<String>, existingAliases: Set<String>) async {
        results = []
        takenAliases = existingAliases
        phase = .scanning(probed: 0, total: candidates.count)

        let timeout = probeTimeout
        var probed = 0

        await withTaskGroup(of: (ip: String, open: Bool).self) { group in
            var iterator = candidates.makeIterator()
            var active = 0

            func addNext() {
                guard !Task.isCancelled, let ip = iterator.next() else { return }
                active += 1
                group.addTask {
                    (ip, await Reachability.probe(host: ip, port: 22, timeout: timeout))
                }
            }

            for _ in 0..<maxInFlight { addNext() }

            while active > 0, let finished = await group.next() {
                active -= 1
                probed += 1
                if case .scanning = phase {
                    phase = .scanning(probed: probed, total: candidates.count)
                }
                if finished.open {
                    appendResponder(ip: finished.ip, existingHostNames: existingHostNames)
                }
                addNext()
            }
        }

        if !Task.isCancelled {
            phase = .done(found: results.count)
        } else {
            phase = .idle
        }
    }

    private func appendResponder(ip: String, existingHostNames: Set<String>) {
        let ipAlias = Self.aliasFromIP(ip)
        let alias = claimUniqueAlias(base: ipAlias)
        let already = existingHostNames.contains(ip)
        let entry = Discovered(
            ip: ip,
            name: nil,
            alias: alias,
            ipDerivedAlias: alias,
            isSelected: !already,
            alreadyInConfig: already
        )
        results.append(entry)
        resolveName(for: entry.id, ip: ip)
    }

    /// Reverse-DNS a responder in the background; when a name resolves, store it
    /// and — only if the user hasn't already renamed the row — refine the alias
    /// from the name.
    private func resolveName(for id: UUID, ip: String) {
        Task { [weak self] in
            guard let name = await LocalNetwork.reverseDNS(ip) else { return }
            guard let self else { return }
            guard let index = self.results.firstIndex(where: { $0.id == id }) else { return }
            self.results[index].name = name
            let refined = SSHHost.sanitizeAliasToken(name)
            guard !refined.isEmpty,
                  self.results[index].alias == self.results[index].ipDerivedAlias else { return }
            self.results[index].alias = self.claimUniqueAlias(base: refined)
        }
    }

    /// An IP-derived alias fallback: `192.168.1.20` -> `192-168-1-20` (a legal,
    /// whitespace-free `Host` token — see `HostsFileBlock.hostnameAllowedCharacters`).
    static func aliasFromIP(_ ip: String) -> String {
        ip.replacingOccurrences(of: ".", with: "-")
    }

    /// Returns `base` if free, otherwise appends `-2`, `-3`, … until unique, and
    /// records the result so later suggestions don't collide with it.
    private func claimUniqueAlias(base: String) -> String {
        let root = base.isEmpty ? "host" : base
        if !takenAliases.contains(root) {
            takenAliases.insert(root)
            return root
        }
        var n = 2
        while takenAliases.contains("\(root)-\(n)") { n += 1 }
        let result = "\(root)-\(n)"
        takenAliases.insert(result)
        return result
    }
}
