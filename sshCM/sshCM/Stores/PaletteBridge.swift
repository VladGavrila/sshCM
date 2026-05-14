import Foundation
import Observation

@MainActor
@Observable
final class PaletteBridge {
    var pendingEdit: SSHHost?
    var pendingDelete: SSHHost?
}
