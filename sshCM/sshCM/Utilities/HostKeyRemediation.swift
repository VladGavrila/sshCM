import AppKit

/// Modal shown when the user connects to a host whose SSH key has changed.
/// Presents the new fingerprint and the three remediation choices. The helper
/// only collects the choice; the caller performs the side effects (removal,
/// persisting bypass, launching) so the same dialog works from both the main
/// window and the AppKit command palette.
enum HostKeyRemediation {
    enum Choice {
        case removeOffending
        case bypassOnce
        case bypassPersist
        case cancel
    }

    @MainActor
    static func present(hostTitle: String, target: String, fingerprint: String) -> Choice {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Host key for \(hostTitle) has changed"
        alert.informativeText = """
        The SSH host key presented by this server no longer matches the one in \
        your known_hosts file. This can happen after a legitimate server rebuild \
        — but it is also exactly what a man-in-the-middle attack looks like.

        Only proceed if you can verify this new key out-of-band.

        Entry: \(target)
        New key: \(fingerprint)
        """

        // NSAlert renders buttons right-to-left in the order added; the first is
        // the default (highlighted) one.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove Old Key…")
        alert.addButton(withTitle: "Connect Once Without Checking")
        alert.addButton(withTitle: "Always Bypass for This Host")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .cancel
        case .alertSecondButtonReturn: return .removeOffending
        case .alertThirdButtonReturn: return .bypassOnce
        default: return .bypassPersist
        }
    }
}
