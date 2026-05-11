import SwiftUI

struct SeedKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultTerminalAppPath") private var terminalAppPath: String = TerminalLauncher.defaultTerminalAppPath

    let host: SSHHost

    enum Stage: Equatable {
        case noKeys
        case offer
        case generating
        case running
        case success
        case failure(title: String, detail: String)
    }

    struct WatchFiles: Equatable, Hashable {
        enum Kind: Hashable { case copy, keygen }
        let kind: Kind
        let status: URL
        let log: URL
    }

    @State private var stage: Stage
    @State private var keys: [URL]
    @State private var selectedKey: URL?
    @State private var launchError: String?
    @State private var watchFiles: WatchFiles?
    @State private var keysBeforeKeygen: [URL] = []

    init(host: SSHHost) {
        self.host = host
        let discovered = PublicKeyDiscovery.discover()
        _keys = State(initialValue: discovered)
        _selectedKey = State(initialValue: discovered.first)
        _stage = State(initialValue: discovered.isEmpty ? .noKeys : .offer)
    }

    private var alias: String? {
        host.aliases.first.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var loginTarget: String {
        let userPart = host.user?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let hostPart = host.hostName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? alias
            ?? host.title
        if let userPart {
            return "\(userPart)@\(hostPart)"
        }
        return hostPart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            Group {
                switch stage {
                case .noKeys:
                    noKeysView
                case .offer:
                    offerView
                case .generating:
                    generatingView
                case .running:
                    runningView
                case .success:
                    successView
                case .failure(let title, let detail):
                    failureView(title: title, detail: detail)
                }
            }

            if let launchError {
                Text(launchError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Spacer()
                buttons
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 220)
        .task(id: watchFiles) {
            guard let watchFiles else { return }
            await waitForCompletion(watchFiles)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Set Up Key Authentication")
                .font(.headline)
            Text(host.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var noKeysView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No public key found in ~/.ssh.")
            Text("Click Generate Key and follow the terminal instructions.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var offerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if keys.count == 1, let key = keys.first {
                Text("Seed your public key into \(Text("~/.ssh/authorized_keys").font(.system(.body, design: .monospaced))) on this host so you can use key-based authentication?")
                    .fixedSize(horizontal: false, vertical: true)
                Text(key.path)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Choose a public key to seed into \(Text("~/.ssh/authorized_keys").font(.system(.body, design: .monospaced))) on this host:")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("", selection: $selectedKey) {
                    ForEach(keys, id: \.self) { url in
                        Text(url.lastPathComponent).tag(Optional(url))
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Terminal will prompt for the password of \(loginTarget).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var generatingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for ssh-keygen to finish in Terminal…")
                Text("Follow the prompts in the Terminal window. sshCM will continue with key setup once the key is created.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runningView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for ssh-copy-id to finish in Terminal…")
                Text("Enter the password for \(loginTarget) in the Terminal window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var successView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Public key installed on \(loginTarget).")
                Text("You can now connect without entering a password.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failureView(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch stage {
        case .noKeys:
            Button("Not Now") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Generate Key") { generateKey() }
                .keyboardShortcut(.defaultAction)
        case .offer:
            Button("Not Now") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Set Up", action: copyKey)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedKey == nil || alias == nil)
        case .generating, .running:
            Button("Hide") { dismiss() }
                .keyboardShortcut(.cancelAction)
        case .success, .failure:
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func copyKey() {
        guard let key = selectedKey, let alias else { return }
        let tmp = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        let statusURL = tmp.appendingPathComponent("sshcm-status-\(token)")
        let logURL = tmp.appendingPathComponent("sshcm-log-\(token)")

        let escapedKey = shellQuote(key.path)
        let escapedAlias = shellQuote(alias)
        let escapedStatus = shellQuote(statusURL.path)
        let escapedLog = shellQuote(logURL.path)

        let command = """
        ssh-copy-id -i \(escapedKey) \(escapedAlias) 2>&1 | tee \(escapedLog)
        rc=${PIPESTATUS[0]}
        printf '%s' "$rc" > \(escapedStatus)
        echo
        if [ "$rc" -eq 0 ]; then
          echo "Key installed successfully. You can close this window."
        else
          echo "ssh-copy-id failed (exit $rc). You can close this window."
        fi
        """

        do {
            try TerminalLauncher.launchCommand(command, terminalAppPath: terminalAppPath)
            launchError = nil
            stage = .running
            watchFiles = WatchFiles(kind: .copy, status: statusURL, log: logURL)
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func generateKey() {
        let tmp = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        let statusURL = tmp.appendingPathComponent("sshcm-keygen-status-\(token)")
        let logURL = tmp.appendingPathComponent("sshcm-keygen-log-\(token)")

        let escapedStatus = shellQuote(statusURL.path)
        let escapedLog = shellQuote(logURL.path)

        let command = """
        ssh-keygen -t ed25519 2>&1 | tee \(escapedLog)
        rc=${PIPESTATUS[0]}
        printf '%s' "$rc" > \(escapedStatus)
        echo
        if [ "$rc" -eq 0 ]; then
          echo "Key created. You can close this window — sshCM will continue with key setup."
        else
          echo "ssh-keygen failed (exit $rc). You can close this window."
        fi
        """

        do {
            try TerminalLauncher.launchCommand(command, terminalAppPath: terminalAppPath)
            launchError = nil
            keysBeforeKeygen = PublicKeyDiscovery.discover()
            stage = .generating
            watchFiles = WatchFiles(kind: .keygen, status: statusURL, log: logURL)
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func waitForCompletion(_ files: WatchFiles) async {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if Task.isCancelled { return }
            if FileManager.default.fileExists(atPath: files.status.path) {
                let rc = (try? String(contentsOf: files.status, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                handleCompletion(kind: files.kind, exitCode: rc, logURL: files.log)
                try? FileManager.default.removeItem(at: files.status)
                try? FileManager.default.removeItem(at: files.log)
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if !Task.isCancelled {
            switch files.kind {
            case .copy:
                stage = .failure(title: "ssh-copy-id failed.", detail: "Timed out waiting for ssh-copy-id to finish.")
            case .keygen:
                stage = .failure(title: "ssh-keygen failed.", detail: "Timed out waiting for ssh-keygen to finish.")
            }
        }
    }

    private func handleCompletion(kind: WatchFiles.Kind, exitCode: String, logURL: URL) {
        switch kind {
        case .copy:
            if exitCode == "0" {
                stage = .success
            } else {
                let detail = failureDetail(command: "ssh-copy-id", logURL: logURL, exitCode: exitCode)
                stage = .failure(title: "ssh-copy-id failed.", detail: detail)
            }
        case .keygen:
            if exitCode == "0" {
                let after = PublicKeyDiscovery.discover()
                let before = Set(keysBeforeKeygen)
                let newKeys = after.filter { !before.contains($0) }
                keys = after
                if let newKey = newKeys.first {
                    selectedKey = newKey
                } else if selectedKey == nil {
                    selectedKey = after.first
                }
                if after.isEmpty {
                    stage = .failure(
                        title: "ssh-keygen finished but no key was found.",
                        detail: "No .pub file appeared in ~/.ssh. Try generating a key again."
                    )
                } else {
                    stage = .offer
                }
            } else {
                let detail = failureDetail(command: "ssh-keygen", logURL: logURL, exitCode: exitCode)
                stage = .failure(title: "ssh-keygen failed.", detail: detail)
            }
        }
    }

    private func failureDetail(command: String, logURL: URL, exitCode: String) -> String {
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let lastLine = log
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        if let lastLine, !lastLine.isEmpty {
            return lastLine
        }
        return "\(command) exited with code \(exitCode.isEmpty ? "?" : exitCode)."
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
