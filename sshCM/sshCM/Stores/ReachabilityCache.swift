import SwiftUI
import Observation

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
}
