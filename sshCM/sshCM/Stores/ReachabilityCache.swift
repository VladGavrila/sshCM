import SwiftUI
import Observation
import Foundation

enum ReachStatus: Equatable {
    case checking, reachable, unreachable

    var color: Color {
        switch self {
        case .checking: return .orange
        case .reachable: return .green
        case .unreachable: return .red
        }
    }

    var help: String {
        switch self {
        case .checking: return "Checking reachability…"
        case .reachable: return "Host is reachable"
        case .unreachable: return "Host is not reachable"
        }
    }
}

/// Second-pass result: whether the host's SSH key still matches `known_hosts`.
/// Only `.changed` surfaces a warning in the UI; everything else is silent.
enum HostKeyState: Equatable {
    case unchecked, checking, ok, changed(fingerprint: String)

    var isChanged: Bool {
        if case .changed = self { return true }
        return false
    }
}

/// Whether a host would let you in on key authentication alone, per
/// `KeyAuthChecker`. `.needsSetup` is the only state the UI acts on (it shows
/// the "Set Up Key Authentication" affordance); `.checking`/`.unchecked` stay
/// silent so the icon doesn't flash in before the check completes.
enum KeyAuthState: Equatable {
    case unchecked, checking, passwordless, needsSetup
}

@MainActor
@Observable
final class ReachabilityCache {
    private var statuses: [String: ReachStatus] = [:]
    private var keyStatuses: [String: HostKeyState] = [:]
    /// Deliberately a separate dict from `statuses`/`keyStatuses`: those are
    /// cleared by `clear()`/`invalidate()` so Refresh and zone switches
    /// re-probe them, but `runKeyAuthCheck` is a real authentication attempt
    /// against the server — re-running it on every Refresh would hit the
    /// server's auth log (and any fail2ban-style rate limiter) far more than
    /// a reachability check should. It's computed at most once per host per
    /// app session; `invalidateKeyAuth` is the only way to force a recheck.
    private var keyAuthStates: [String: KeyAuthState] = [:]
    private(set) var epoch: Int = 0

    func status(for key: String) -> ReachStatus? {
        statuses[key]
    }

    func set(_ status: ReachStatus, for key: String) {
        statuses[key] = status
    }

    func keyStatus(for key: String) -> HostKeyState {
        keyStatuses[key] ?? .unchecked
    }

    func setKeyStatus(_ status: HostKeyState, for key: String) {
        keyStatuses[key] = status
    }

    /// The host-key warning state for a host, if its probe target resolves.
    func keyState(for host: SSHHost) -> HostKeyState {
        guard let cacheKey = Self.cacheKey(for: host) else { return .unchecked }
        return keyStatus(for: cacheKey)
    }

    func keyAuthState(for host: SSHHost) -> KeyAuthState {
        guard let cacheKey = Self.cacheKey(for: host) else { return .unchecked }
        return keyAuthStates[cacheKey] ?? .unchecked
    }

    /// Forces a recheck next time `runKeyAuthCheck` runs for this host — used
    /// after the user runs "Set Up Key Authentication" so the indicator
    /// updates without waiting for the next natural probe cycle.
    func invalidateKeyAuth(for host: SSHHost) {
        guard let cacheKey = Self.cacheKey(for: host) else { return }
        keyAuthStates.removeValue(forKey: cacheKey)
    }

    func clear() {
        statuses.removeAll()
        keyStatuses.removeAll()
        epoch &+= 1
    }

    /// Drops cached status only for `hosts`, bumping `epoch` so `.task(id:)`
    /// restarts and re-probes them. Hosts outside a refresh's scope (e.g. a
    /// zone filter) keep their last-known status instead of going back to
    /// unknown — a full `clear()` would erase them even though they were
    /// never touched by this refresh, only to force a surprise reprobe of
    /// everything the moment the filter is lifted.
    func invalidate(hosts: [SSHHost]) {
        for host in hosts {
            guard let key = Self.cacheKey(for: host) else { continue }
            statuses.removeValue(forKey: key)
            keyStatuses.removeValue(forKey: key)
        }
        epoch &+= 1
    }

    static func probeTarget(for host: SSHHost) -> (target: String, port: Int)? {
        let candidates = [host.hostName, host.aliases.first]
        let target = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let target else { return nil }
        return (target, host.port ?? 22)
    }

    static func cacheKey(for host: SSHHost) -> String? {
        guard let pt = probeTarget(for: host) else { return nil }
        return "\(pt.target):\(pt.port)"
    }

    func runProbe(for host: SSHHost) async {
        guard let probe = Self.probeTarget(for: host),
              let cacheKey = Self.cacheKey(for: host) else { return }
        if let cached = status(for: cacheKey), cached != .checking { return }
        set(.checking, for: cacheKey)
        let success = await Reachability.probe(host: probe.target, port: probe.port)
        guard !Task.isCancelled else { return }
        set(success ? .reachable : .unreachable, for: cacheKey)
        if success {
            await runKeyCheck(for: host)
            await runKeyAuthCheck(for: host)
        }
    }

    /// Second pass: only runs for reachable hosts (so it never eats a keyscan
    /// timeout on a dead host) and only once per host per epoch.
    func runKeyCheck(for host: SSHHost) async {
        guard let probe = Self.probeTarget(for: host),
              let cacheKey = Self.cacheKey(for: host) else { return }
        switch keyStatus(for: cacheKey) {
        case .unchecked: break
        default: return
        }
        setKeyStatus(.checking, for: cacheKey)
        let status = await HostKeyVerifier.verify(host: probe.target, port: probe.port)
        guard !Task.isCancelled else { return }
        switch status {
        case .changed(let fp): setKeyStatus(.changed(fingerprint: fp), for: cacheKey)
        case .ok: setKeyStatus(.ok, for: cacheKey)
        case .unknown, .indeterminate: setKeyStatus(.ok, for: cacheKey)
        }
    }

    /// Whether the host would let you in on key auth alone (`KeyAuthChecker`).
    /// Only runs for reachable hosts, and only once per host per app session —
    /// see the `keyAuthStates` doc comment for why it isn't epoch-invalidated
    /// like `runProbe`/`runKeyCheck`. Safe to call directly (e.g. right after
    /// the user finishes "Set Up Key Authentication") as well as from
    /// `runProbe`'s success branch: the reachability guard below makes it a
    /// no-op for a host that isn't currently known-reachable.
    func runKeyAuthCheck(for host: SSHHost) async {
        guard let alias = host.aliases.first, !alias.isEmpty,
              let cacheKey = Self.cacheKey(for: host),
              status(for: cacheKey) == .reachable else { return }
        switch keyAuthStates[cacheKey] ?? .unchecked {
        case .unchecked: break
        default: return
        }
        keyAuthStates[cacheKey] = .checking
        let passwordless = await KeyAuthChecker.check(alias: alias)
        guard !Task.isCancelled else { return }
        keyAuthStates[cacheKey] = passwordless ? .passwordless : .needsSetup
    }
}
