import Foundation

/// Result of comparing a host's currently-presented SSH host keys against the
/// keys stored in `~/.ssh/known_hosts`.
enum HostKeyStatus: Equatable {
    /// Stored keys match what the server currently presents.
    case ok
    /// A key type is present in both, but the key itself differs — this is the
    /// dangerous case that makes ssh print "REMOTE HOST IDENTIFICATION HAS
    /// CHANGED". `fingerprint` is the SHA256 fingerprint of the new key.
    case changed(fingerprint: String)
    /// No stored entry for this host yet (trust-on-first-use), so there is
    /// nothing to compare against.
    case unknown
    /// The check could not be completed (host didn't answer the keyscan, tools
    /// missing, certificate-based host keys, etc.). Treated as "no warning".
    case indeterminate
}

/// Detects whether a host's SSH host key has changed since it was recorded in
/// `known_hosts`, using the standard OpenSSH tooling (`ssh-keyscan` to fetch the
/// current keys, `ssh-keygen -F` to read the stored ones). No authentication is
/// performed, so this never triggers password/passphrase prompts.
enum HostKeyVerifier {
    nonisolated private static let keyscanPath = "/usr/bin/ssh-keyscan"
    nonisolated private static let keygenPath = "/usr/bin/ssh-keygen"

    /// The `known_hosts` target string for a host: bare host for the default
    /// port, `[host]:port` otherwise. Reused for detection and removal so they
    /// always agree.
    static func knownHostsTarget(host: String, port: Int) -> String {
        port == 22 ? host : "[\(host)]:\(port)"
    }

    static func verify(host: String, port: Int, timeout: Int = 5) async -> HostKeyStatus {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .indeterminate }

        let scanned = await Task.detached(priority: .utility) {
            scanKeys(host: trimmed, port: port, timeout: timeout)
        }.value
        // Couldn't reach the host for a keyscan (or the tool failed): nothing to
        // say about the key.
        guard !scanned.isEmpty else { return .indeterminate }

        let target = knownHostsTarget(host: trimmed, port: port)
        let stored = await Task.detached(priority: .utility) {
            storedKeys(target: target)
        }.value
        // Never connected before / not pinned: trust-on-first-use, no warning.
        guard !stored.isEmpty else { return .unknown }

        // Compare per key type. `known_hosts` can hold several entries of the
        // same type (a stale key plus the current one); ssh accepts the host if
        // *any* stored key of that type matches, so we do too — matching only the
        // first stored key would raise a false "key changed" alarm. A mismatch is
        // only real when the presented key matches *none* of the stored ones.
        var sawMatch = false
        for (type, scannedKey) in scanned {
            guard let storedForType = stored[type] else { continue }
            if storedForType.contains(scannedKey) {
                sawMatch = true
            } else {
                let fp = await Task.detached(priority: .utility) {
                    fingerprint(type: type, key: scannedKey)
                }.value
                return .changed(fingerprint: fp ?? "\(type) \(String(scannedKey.prefix(20)))…")
            }
        }
        // Stored entry exists but only for key types the server no longer
        // offers (e.g. it dropped RSA): not a mismatch, just stale — don't warn.
        return sawMatch ? .ok : .indeterminate
    }

    // MARK: - Tool invocations

    /// Returns a map of `keytype -> base64 key` from `ssh-keyscan`. Ignores
    /// comment/marker lines. Empty if the host didn't answer.
    nonisolated private static func scanKeys(host: String, port: Int, timeout: Int) -> [String: String] {
        let result = run(keyscanPath, ["-T", String(timeout), "-p", String(port), host])
        guard result.exitCode == 0 else { return [:] }
        return parseKeyLines(result.stdout)
    }

    /// Returns a map of `keytype -> [base64 key]` for `target` from known_hosts —
    /// all stored keys per type, since `known_hosts` may legitimately list more
    /// than one. `ssh-keygen -F` handles hashed entries, which a plain file read
    /// can't.
    nonisolated private static func storedKeys(target: String) -> [String: [String]] {
        // No `-f`: ssh-keygen defaults to the user's ~/.ssh/known_hosts (and
        // known_hosts2). Exit code is non-zero when not found.
        let result = run(keygenPath, ["-F", target])
        guard result.exitCode == 0 else { return [:] }
        return parseKeyLinesGrouped(result.stdout)
    }

    /// SHA256 fingerprint of a single presented key, for display to the user.
    nonisolated private static func fingerprint(type: String, key: String) -> String? {
        let line = "placeholder \(type) \(key)\n"
        guard let data = line.data(using: .utf8) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshcm-hk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try data.write(to: tmp)
        } catch {
            return nil
        }
        let result = run(keygenPath, ["-l", "-f", tmp.path])
        guard result.exitCode == 0 else { return nil }
        // Output: "256 SHA256:abc… placeholder (ED25519)"
        let fields = result.stdout.split(separator: " ")
        return fields.first(where: { $0.hasPrefix("SHA256:") }).map(String.init)
    }

    /// Parses `ssh-keyscan` / `ssh-keygen -F` output lines of the form
    /// `<host> <keytype> <base64>` into `keytype -> base64`. Lines beginning
    /// with `#`, or carrying `@cert-authority` / `@revoked` markers, are
    /// skipped — we only reason about plain host keys.
    nonisolated private static func parseKeyLines(_ text: String) -> [String: String] {
        var keys: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("@") { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3 else { continue }
            let type = String(fields[1])
            let key = String(fields[2])
            // First occurrence wins; both tools emit at most one line per type.
            if keys[type] == nil { keys[type] = key }
        }
        return keys
    }

    /// Like `parseKeyLines`, but keeps *every* key per type rather than only the
    /// first — used for the stored `known_hosts` side, which can list several
    /// keys of the same type (e.g. a rotated-but-not-removed old key).
    nonisolated private static func parseKeyLinesGrouped(_ text: String) -> [String: [String]] {
        var keys: [String: [String]] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("@") { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3 else { continue }
            keys[String(fields[1]), default: []].append(String(fields[2]))
        }
        return keys
    }

    // MARK: - Process helper

    private struct CommandResult {
        let exitCode: Int32
        let stdout: String
    }

    nonisolated private static func run(_ path: String, _ args: [String]) -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return CommandResult(exitCode: -1, stdout: "")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stdout: "")
        }
        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? ""
        )
    }

    /// Removes the offending host key line(s) from `known_hosts`
    /// (`ssh-keygen -R`). Rewrites the file, leaving a `.old` backup. Returns
    /// true on success.
    @discardableResult
    static func removeStoredKey(host: String, port: Int) -> Bool {
        let target = knownHostsTarget(host: host, port: port)
        return run(keygenPath, ["-R", target]).exitCode == 0
    }
}
