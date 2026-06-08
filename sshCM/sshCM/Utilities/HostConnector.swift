import Foundation

/// Single entry point for launching an SSH session, shared by the main window
/// and the command palette. Centralises the host-key gate so both paths behave
/// identically: a persisted bypass connects straight through, a changed key
/// surfaces the warning sheet, and everything else connects normally.
@MainActor
enum HostConnector {
    /// Describes a host whose presented SSH key no longer matches `known_hosts`.
    /// Returned by `connect` so the caller can present `HostKeyWarningSheet`; the
    /// user's choice is then routed back through the `resolve*` helpers below.
    struct KeyWarning: Identifiable, Equatable {
        let id = UUID()
        let host: SSHHost
        let user: String?
        /// `-L` / `-R` forward specs to apply once the warning is resolved, so a
        /// tunnel connection still forwards after host-key remediation. Empty for
        /// a plain connect.
        var localForwards: [String] = []
        var remoteForwards: [String] = []
        /// The `known_hosts` entry string (bare host, or `[host]:port`), shown
        /// to the user.
        let target: String
        /// SHA256 fingerprint of the newly-presented key.
        let fingerprint: String
    }

    /// Launches SSH for `host`, or returns a `KeyWarning` to present when the
    /// host's key has changed and isn't already bypassed. Throws only on
    /// terminal-launch failure (e.g. invalid alias). A `nil` return means a
    /// session was launched.
    static func connect(
        to host: SSHHost,
        as user: String? = nil,
        localForwards: [String] = [],
        remoteForwards: [String] = [],
        reachCache: ReachabilityCache,
        bypassStore: HostKeyBypassStore,
        terminalAppPath: String
    ) throws -> KeyWarning? {
        guard let alias = host.aliases.first, !alias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }

        // Persisted opt-out: connect with checking disabled, no prompt.
        if bypassStore.isBypassed(alias) {
            try TerminalLauncher.launchSSH(
                toAlias: alias, user: user, bypassHostKey: true,
                localForwards: localForwards, remoteForwards: remoteForwards,
                terminalAppPath: terminalAppPath
            )
            return nil
        }

        // Changed key → hand the caller a warning to review before connecting.
        if case .changed(let fingerprint) = reachCache.keyState(for: host),
           let probe = ReachabilityCache.probeTarget(for: host) {
            let target = HostKeyVerifier.knownHostsTarget(host: probe.target, port: probe.port)
            return KeyWarning(
                host: host, user: user,
                localForwards: localForwards, remoteForwards: remoteForwards,
                target: target, fingerprint: fingerprint
            )
        }

        // Normal path.
        try TerminalLauncher.launchSSH(
            toAlias: alias, user: user,
            localForwards: localForwards, remoteForwards: remoteForwards,
            terminalAppPath: terminalAppPath
        )
        return nil
    }

    // MARK: - Warning-sheet choice handlers

    /// Removes the offending `known_hosts` entry and clears the warning so the
    /// next connection re-learns the key via trust-on-first-use. Does not
    /// connect; the sheet then offers re-seeding or connecting.
    @discardableResult
    static func removeOldKey(for warning: KeyWarning, reachCache: ReachabilityCache) -> Bool {
        guard let probe = ReachabilityCache.probeTarget(for: warning.host),
              let cacheKey = ReachabilityCache.cacheKey(for: warning.host) else { return false }
        let removed = HostKeyVerifier.removeStoredKey(host: probe.target, port: probe.port)
        reachCache.setKeyStatus(.ok, for: cacheKey)
        return removed
    }

    /// Opens a normal SSH session for the warning's host.
    static func connectNormally(_ warning: KeyWarning, terminalAppPath: String) throws {
        guard let alias = warning.host.aliases.first, !alias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }
        try TerminalLauncher.launchSSH(
            toAlias: alias, user: warning.user,
            localForwards: warning.localForwards, remoteForwards: warning.remoteForwards,
            terminalAppPath: terminalAppPath
        )
    }

    /// Connects with strict host-key checking disabled. When `persist` is true,
    /// the choice is remembered for future connections.
    static func connectBypassing(
        _ warning: KeyWarning,
        persist: Bool,
        bypassStore: HostKeyBypassStore,
        terminalAppPath: String
    ) throws {
        guard let alias = warning.host.aliases.first, !alias.isEmpty else {
            throw TerminalLaunchError.invalidAlias
        }
        if persist {
            bypassStore.setBypassed(true, for: alias)
        }
        try TerminalLauncher.launchSSH(
            toAlias: alias, user: warning.user, bypassHostKey: true,
            localForwards: warning.localForwards, remoteForwards: warning.remoteForwards,
            terminalAppPath: terminalAppPath
        )
    }
}
