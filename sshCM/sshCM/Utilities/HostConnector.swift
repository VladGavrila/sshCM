import Foundation

/// Single entry point for launching an SSH session, shared by the main window
/// and the command palette. Centralises the host-key gate so both paths behave
/// identically: a persisted bypass connects straight through, a changed key
/// opens the remediation dialog, and everything else connects normally.
@MainActor
enum HostConnector {
    /// Launches SSH for `host`. Throws only on terminal-launch failure; the
    /// host-key dialog and a user cancel are handled internally (a cancel is a
    /// silent no-op).
    static func connect(
        to host: SSHHost,
        as user: String? = nil,
        reachCache: ReachabilityCache,
        bypassStore: HostKeyBypassStore,
        terminalAppPath: String
    ) throws {
        guard let alias = host.aliases.first, !alias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }

        // Persisted opt-out: connect with checking disabled, no prompt.
        if bypassStore.isBypassed(alias) {
            try TerminalLauncher.launchSSH(
                toAlias: alias, user: user, bypassHostKey: true, terminalAppPath: terminalAppPath
            )
            return
        }

        // Changed key → review before connecting.
        if case .changed(let fingerprint) = reachCache.keyState(for: host),
           let probe = ReachabilityCache.probeTarget(for: host),
           let cacheKey = ReachabilityCache.cacheKey(for: host) {
            let target = HostKeyVerifier.knownHostsTarget(host: probe.target, port: probe.port)
            switch HostKeyRemediation.present(
                hostTitle: host.title, target: target, fingerprint: fingerprint
            ) {
            case .cancel:
                return
            case .removeOffending:
                HostKeyVerifier.removeStoredKey(host: probe.target, port: probe.port)
                // Old key gone; clear the warning and connect normally (the
                // next connection re-learns the key via trust-on-first-use).
                reachCache.setKeyStatus(.ok, for: cacheKey)
                try TerminalLauncher.launchSSH(
                    toAlias: alias, user: user, terminalAppPath: terminalAppPath
                )
            case .bypassOnce:
                try TerminalLauncher.launchSSH(
                    toAlias: alias, user: user, bypassHostKey: true, terminalAppPath: terminalAppPath
                )
            case .bypassPersist:
                bypassStore.setBypassed(true, for: alias)
                try TerminalLauncher.launchSSH(
                    toAlias: alias, user: user, bypassHostKey: true, terminalAppPath: terminalAppPath
                )
            }
            return
        }

        // Normal path.
        try TerminalLauncher.launchSSH(
            toAlias: alias, user: user, terminalAppPath: terminalAppPath
        )
    }
}
