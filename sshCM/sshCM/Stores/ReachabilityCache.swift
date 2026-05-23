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

@MainActor
@Observable
final class ReachabilityCache {
    private var statuses: [String: ReachStatus] = [:]
    private(set) var epoch: Int = 0

    func status(for key: String) -> ReachStatus? {
        statuses[key]
    }

    func set(_ status: ReachStatus, for key: String) {
        statuses[key] = status
    }

    func clear() {
        statuses.removeAll()
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
    }
}
