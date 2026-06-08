import Foundation
import Observation

@MainActor
@Observable
final class PaletteBridge {
    var pendingEdit: SSHHost?
    var pendingDelete: SSHHost?
    var pendingAdd: Bool = false
    /// Set when a connect launched from the palette hits a changed host key.
    /// `ContentView` drains this and presents `HostKeyWarningSheet`, since the
    /// palette lives outside the SwiftUI window.
    var pendingKeyWarning: HostConnector.KeyWarning?
}
