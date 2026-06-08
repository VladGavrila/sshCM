import Foundation

/// A single SSH port-forwarding entry. `spec` is exactly what follows `-L`/`-R`
/// on the ssh command line (e.g. `8080:localhost:8080`); `note` is a free-text
/// label for the user's benefit and is **never** placed on the command line.
///
/// These are stored as sshCM metadata comments in `~/.ssh/config` (see
/// `SSHConfigParser.localForwardMarker` / `remoteForwardMarker`) rather than as
/// native `LocalForward`/`RemoteForward` directives, so a plain `ssh host`
/// connection does not forward — the flags are injected only when the user
/// explicitly picks a tunnel action.
struct PortForward: Hashable {
    var spec: String
    var note: String

    init(spec: String, note: String = "") {
        self.spec = spec
        self.note = note
    }
}
