import SwiftUI

struct AddHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var store
    @Environment(TagsStore.self) private var tagsStore
    @Environment(HostKeyBypassStore.self) private var bypassStore
    @Environment(RemoteAppsStore.self) private var remoteAppsStore

    @AppStorage(AppStorageKey.defaultMacOSVNCAppPath.rawValue) private var macOSVNCAppPath: String = VNCLauncher.defaultMacOSVNCAppPath

    let editing: SSHHost?
    var onSaved: ((SSHHost, _ isNew: Bool, _ addedAlternateUsers: [String]) -> Void)?

    @State private var alias: String
    @State private var searchAliases: String
    @State private var hostName: String
    @State private var user: String
    @State private var portText: String
    @State private var showAdvanced: Bool
    @State private var identityFile: String
    @State private var proxyJump: String
    @State private var alternateUsers: String
    @State private var forwards: [ForwardDraft]
    @State private var showForwarding: Bool
    @State private var tag: HostTag?
    @State private var showTagPicker: Bool = false
    @State private var hasBypass: Bool = false
    @State private var remoteAppName: String?
    @State private var vncPortText: String
    /// Transient messages shown when the user types a character that isn't valid in
    /// an alias (e.g. a space); the character is stripped rather than entered.
    @State private var aliasRejectionNotice: String? = nil
    @State private var searchAliasRejectionNotice: String? = nil
    /// Guards against the re-entrant `onChange` fired by our own sanitising write,
    /// which would otherwise immediately clear the rejection notice.
    @State private var suppressAliasFilter = false
    @State private var suppressSearchFilter = false

    init(
        editing: SSHHost? = nil,
        onSaved: ((SSHHost, _ isNew: Bool, _ addedAlternateUsers: [String]) -> Void)? = nil
    ) {
        self.editing = editing
        self.onSaved = onSaved
        let initialAlias = editing?.aliases.first ?? ""
        let initialSearchAliases = editing?.searchAliases.joined(separator: ",") ?? ""
        let initialHostName = editing?.hostName ?? ""
        let initialUser = editing?.user ?? ""
        let initialPort = editing.flatMap { $0.port.map(String.init) } ?? "22"
        let initialIdentity = editing?.identityFile ?? ""
        let initialProxy = editing?.proxyJump ?? ""
        let initialAlternateUsers = editing?.alternateUsers.joined(separator: ", ") ?? ""
        let initialVNCPort = editing.flatMap { $0.vncPort.map(String.init) } ?? "5900"
        let hasAdvanced = !initialIdentity.isEmpty || !initialProxy.isEmpty || editing?.remoteApp != nil || editing?.vncPort != nil
        let initialForwards =
            (editing?.localForwards.map { ForwardDraft(direction: .local, parsing: $0.spec, note: $0.note) } ?? [])
            + (editing?.remoteForwards.map { ForwardDraft(direction: .remote, parsing: $0.spec, note: $0.note) } ?? [])

        _alias = State(initialValue: initialAlias)
        _searchAliases = State(initialValue: initialSearchAliases)
        _hostName = State(initialValue: initialHostName)
        _user = State(initialValue: initialUser)
        _portText = State(initialValue: initialPort)
        _identityFile = State(initialValue: initialIdentity)
        _proxyJump = State(initialValue: initialProxy)
        _alternateUsers = State(initialValue: initialAlternateUsers)
        _forwards = State(initialValue: initialForwards)
        _showForwarding = State(initialValue: !initialForwards.isEmpty)
        _showAdvanced = State(initialValue: hasAdvanced)
        _remoteAppName = State(initialValue: editing?.remoteApp)
        _vncPortText = State(initialValue: initialVNCPort)
    }

    private var portValue: Int? {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var portIsValid: Bool {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if let p = Int(trimmed), p > 0, p < 65536 { return true }
        return false
    }

    private var vncPortValue: Int? {
        let trimmed = vncPortText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var vncPortIsValid: Bool {
        let trimmed = vncPortText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if let p = Int(trimmed), p > 0, p < 65536 { return true }
        return false
    }

    /// Every selectable remote app, with the built-in Screen Sharing entry first.
    private var selectableRemoteApps: [RemoteAccessApp] {
        remoteAppsStore.selectableApps(screenSharingPath: macOSVNCAppPath)
    }

    /// Whether the VNC port field applies to the currently selected remote app.
    /// Hidden for apps that connect by their own identifier (TeamViewer, RustDesk, …)
    /// and for "Unset".
    private var showsVNCPort: Bool {
        guard let remoteAppName else { return false }
        return selectableRemoteApps.first { $0.name == remoteAppName }?.showsPort ?? false
    }

    private static let aliasRejectionMessage =
        "Spaces and special characters aren't allowed — use letters, digits, - . or _."
    private static let searchAliasRejectionMessage =
        "Separate aliases with commas — spaces and special characters aren't allowed."

    /// Strips every character that isn't valid in an SSH alias / `/etc/hosts`
    /// hostname, using the shared allowed set. The search-aliases field also keeps
    /// commas, which separate the individual aliases.
    private static func sanitizeAlias(_ value: String, allowComma: Bool) -> String {
        var allowed = HostsFileBlock.hostnameAllowedCharacters
        if allowComma { allowed.insert(charactersIn: ",") }
        return String(String.UnicodeScalarView(
            value.unicodeScalars.filter { allowed.contains($0) }
        ))
    }

    /// Live-filters a text field as the user types: disallowed characters are
    /// dropped rather than entered (so they never render), and `notice` is set the
    /// moment one is rejected. The `suppress` flag absorbs the re-entrant
    /// `onChange` triggered by our own write so the notice isn't instantly cleared.
    private func filterAliasInput(
        _ newValue: String,
        into text: Binding<String>,
        allowComma: Bool,
        suppress: Binding<Bool>,
        notice: Binding<String?>,
        message: String
    ) {
        if suppress.wrappedValue {
            suppress.wrappedValue = false
            return
        }
        let sanitized = AddHostSheet.sanitizeAlias(newValue, allowComma: allowComma)
        if sanitized != newValue {
            suppress.wrappedValue = true
            text.wrappedValue = sanitized
            notice.wrappedValue = message
        } else {
            notice.wrappedValue = nil
        }
    }

    private var advancedBinding: Binding<Bool> {
        Binding(
            get: { showAdvanced },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) { showAdvanced = newValue }
            }
        )
    }

    private var canSave: Bool {
        !alias.trimmed.isEmpty
        && aliasError == nil
        && !hostName.trimmed.isEmpty
        && !user.trimmed.isEmpty
        && portIsValid
        && vncPortIsValid
        && forwardsAreValid
    }

    /// Every non-empty forward row must be fully valid. Fully-empty rows are
    /// ignored on save, so they don't block it.
    private var forwardsAreValid: Bool {
        forwards.allSatisfy { draftIsEmpty($0) || draftIsComplete($0) }
    }

    private func draftIsEmpty(_ d: ForwardDraft) -> Bool {
        d.bindPort.trimmed.isEmpty && d.host.trimmed.isEmpty && d.hostPort.trimmed.isEmpty
    }

    private func draftIsComplete(_ d: ForwardDraft) -> Bool {
        isValidPortField(d.bindPort) && isValidHostField(d.host) && isValidPortField(d.hostPort)
    }

    private func isValidPortField(_ value: String) -> Bool {
        guard let p = Int(value.trimmed) else { return false }
        return p > 0 && p <= 65535
    }

    private func isValidHostField(_ value: String) -> Bool {
        HostsFileBlock.isPublishableHostname(value.trimmed)
    }

    private var forwardingBinding: Binding<Bool> {
        Binding(
            get: { showForwarding },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) { showForwarding = newValue }
            }
        )
    }

    /// Validation for the SSH alias: it must be a single token usable as a `Host`
    /// pattern (no spaces/special chars) and unique across hosts, otherwise two
    /// hosts can claim the same alias and `ssh <alias>` connects to the wrong one.
    private var aliasError: String? {
        let value = alias.trimmed
        guard !value.isEmpty else { return nil }
        guard HostsFileBlock.isPublishableHostname(value) else {
            return "Alias can't contain spaces or special characters (use - . _)."
        }
        let collides = store.file.hosts.contains { host in
            host.id != editing?.id && host.aliases.contains(value)
        }
        if collides {
            return "Alias '\(value)' is already used by another host."
        }
        return nil
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Host") {
                    HStack(spacing: 8) {
                        TextField("Alias", text: $alias, prompt: Text("e.g. prod-bastion"))
                            .onChange(of: alias) { _, newValue in
                                filterAliasInput(
                                    newValue,
                                    into: $alias,
                                    allowComma: false,
                                    suppress: $suppressAliasFilter,
                                    notice: $aliasRejectionNotice,
                                    message: AddHostSheet.aliasRejectionMessage
                                )
                            }
                        tagButton
                    }
                    if let message = aliasRejectionNotice ?? aliasError {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField(
                        "Search aliases",
                        text: $searchAliases,
                        prompt: Text("optional, comma-separated — search only")
                    )
                    .onChange(of: searchAliases) { _, newValue in
                        filterAliasInput(
                            newValue,
                            into: $searchAliases,
                            allowComma: true,
                            suppress: $suppressSearchFilter,
                            notice: $searchAliasRejectionNotice,
                            message: AddHostSheet.searchAliasRejectionMessage
                        )
                    }
                    if let searchAliasRejectionNotice {
                        Text(searchAliasRejectionNotice)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("HostName (IP or FQDN)", text: $hostName, prompt: Text("e.g. 10.0.0.4 or db.example.com"))
                    TextField("User", text: $user, prompt: Text("e.g. ubuntu"))
                    TextField(
                        "Alternate users",
                        text: $alternateUsers,
                        prompt: Text("optional, comma-separated — also connectable")
                    )
                    TextField("Port", text: $portText)
                    if !portIsValid {
                        Text("Port must be between 1 and 65535.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if isEditing && hasBypass {
                    Section("Security") {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Host key checking is bypassed")
                                    .font(.callout)
                                Text("Connections skip strict host-key verification.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove Bypass", role: .destructive, action: removeBypass)
                        }
                    }
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: advancedBinding) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("IdentityFile")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField("", text: $identityFile)
                                Button("Browse…") {
                                    if let url = FilePicker.pickFile() {
                                        identityFile = url.path
                                    }
                                }
                            }
                            HStack {
                                Text("ProxyJump")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField("", text: $proxyJump, prompt: Text("[user@]host[:port] or ssh URI"))
                            }
                            HStack {
                                Text("Remote app")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $remoteAppName) {
                                    Text("Unset").tag(String?.none)
                                    ForEach(selectableRemoteApps) { app in
                                        Text(app.name).tag(String?.some(app.name))
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                                if showsVNCPort {
                                    Text("VNC Port")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    TextField("", text: $vncPortText, prompt: Text("5900"))
                                }
                            }
                            if showsVNCPort, !vncPortIsValid {
                                Text("VNC port must be between 1 and 65535.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Section {
                    DisclosureGroup("Port Forwarding", isExpanded: forwardingBinding) {
                        forwardingContent
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Update" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(minWidth: 540, minHeight: 300)
        .animation(.easeInOut(duration: 0.25), value: showAdvanced)
        .onAppear {
            loadExistingTag()
            hasBypass = editing?.aliases.first.map { bypassStore.isBypassed($0) } ?? false
        }
    }

    @ViewBuilder
    private var forwardingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Forwards are saved with the host but applied only when you pick a tunnel action — a plain connect never forwards.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array($forwards.enumerated()), id: \.element.id) { index, $draft in
                if index > 0 { Divider() }
                forwardRow($draft)
            }

            Button {
                forwards.append(ForwardDraft(direction: .local))
            } label: {
                Label("Add forwarding", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func forwardRow(_ draft: Binding<ForwardDraft>) -> some View {
        let d = draft.wrappedValue
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Picker("", selection: draft.direction) {
                    Text("Local").tag(ForwardDraft.Direction.local)
                    Text("Reverse").tag(ForwardDraft.Direction.remote)
                }
                .labelsHidden()
                .frame(width: 90)
                .help(forwardHelp(d.direction))

                TextField("", text: digitsBinding(draft.bindPort), prompt: Text("8080"))
                    .frame(width: 58)
                helpIcon(bindPortHelp(d.direction))
                Text(":").foregroundStyle(.secondary)
                TextField("", text: draft.host, prompt: Text("localhost"))
                    .frame(minWidth: 80)
                helpIcon(hostHelp(d.direction))
                Text(":").foregroundStyle(.secondary)
                TextField("", text: digitsBinding(draft.hostPort), prompt: Text("8080"))
                    .frame(width: 58)
                helpIcon(hostPortHelp(d.direction))

                Button(role: .destructive) {
                    forwards.removeAll { $0.id == d.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Remove this forward")
            }

            TextField("", text: draft.note, prompt: Text("Description"))

            if !draftIsEmpty(d), !d.host.trimmed.isEmpty, !isValidHostField(d.host) {
                forwardError("Host must be a valid IP or hostname (use letters, digits, - . _).")
            }
            if !draftIsEmpty(d), !draftIsComplete(d),
               d.host.trimmed.isEmpty || isValidHostField(d.host) {
                forwardError("Enter a listening port, host, and destination port (1–65535).")
            }
        }
    }

    private func forwardError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }

    /// Keeps a text field numeric (and within a port's 5-digit ceiling) by
    /// stripping anything else as it's typed.
    private func digitsBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = String($0.filter(\.isNumber).prefix(5)) }
        )
    }

    private func forwardHelp(_ direction: ForwardDraft.Direction) -> String {
        switch direction {
        case .local:
            return "Receive traffic from the server: the bind port opens on this Mac and maps to the host port reached from the server."
        case .remote:
            return "Send traffic to remote: the bind port opens on the server and maps to the host port reached from this Mac."
        }
    }

    private func helpIcon(_ text: String) -> some View {
        Image(systemName: "questionmark.circle")
            .foregroundStyle(.secondary)
            .help(text)
    }

    private func bindPortHelp(_ direction: ForwardDraft.Direction) -> String {
        switch direction {
        case .local:
            return "Bind port — opens on this Mac (local). Connect to localhost:<bind port> and traffic is tunneled to the destination on the right."
        case .remote:
            return "Bind port — opens on the remote server. Anything connecting to the bind port on the server is tunneled to the destination on the right."
        }
    }

    private func hostHelp(_ direction: ForwardDraft.Direction) -> String {
        switch direction {
        case .local:
            return "Destination host, reached from the server's side — e.g. localhost means the server itself."
        case .remote:
            return "Destination host, reached from this Mac's side — e.g. localhost means this Mac."
        }
    }

    private func hostPortHelp(_ direction: ForwardDraft.Direction) -> String {
        switch direction {
        case .local:
            return "Host port — the port on the destination host (server side) that the tunnel connects to."
        case .remote:
            return "Host port — the port on the destination host (this Mac's side) that the tunnel connects to."
        }
    }

    private func removeBypass() {
        guard let alias = editing?.aliases.first else { return }
        bypassStore.setBypassed(false, for: alias)
        hasBypass = false
    }

    private var tagButton: some View {
        Button {
            showTagPicker.toggle()
        } label: {
            Image(systemName: tag == nil ? "tag" : "tag.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tag?.color ?? Color.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(tag.map { "Tag: \(tagsStore.displayName(for: $0))" } ?? "Assign a tag")
        .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
            TagPickerPopover(selection: $tag)
                .environment(tagsStore)
        }
    }

    private func loadExistingTag() {
        guard let alias = editing?.aliases.first, !alias.isEmpty else { return }
        tag = tagsStore.tag(for: alias)
    }

    private func save() {
        let primaryAlias = alias.trimmed
        guard !primaryAlias.isEmpty else { return }
        let aliases = [primaryAlias]
        let parsedSearchAliases = searchAliases
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let parsedAlternateUsers = alternateUsers
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let oldAlternates = editing?.alternateUsers ?? []
        let addedAlternateUsers = parsedAlternateUsers.filter { !oldAlternates.contains($0) }

        func makeForward(_ d: ForwardDraft) -> PortForward {
            PortForward(
                spec: "\(d.bindPort.trimmed):\(d.host.trimmed):\(d.hostPort.trimmed)",
                note: d.note.trimmed
            )
        }
        let completeForwards = forwards.filter { draftIsComplete($0) }
        let parsedLocalForwards = completeForwards.filter { $0.direction == .local }.map(makeForward)
        let parsedRemoteForwards = completeForwards.filter { $0.direction == .remote }.map(makeForward)
        let parsedVNCPort = showsVNCPort ? vncPortValue.flatMap { $0 == 5900 ? nil : $0 } : nil

        let savedHost: SSHHost
        let isNew: Bool
        if let original = editing {
            var updated = original
            updated.aliases = aliases
            updated.searchAliases = parsedSearchAliases
            updated.hostName = hostName.trimmed.nilIfEmpty
            updated.user = user.trimmed.nilIfEmpty
            updated.port = portValue
            updated.identityFile = identityFile.trimmed.nilIfEmpty
            updated.proxyJump = proxyJump.trimmed.nilIfEmpty
            updated.alternateUsers = parsedAlternateUsers
            updated.localForwards = parsedLocalForwards
            updated.remoteForwards = parsedRemoteForwards
            updated.remoteApp = remoteAppName
            updated.vncPort = parsedVNCPort
            store.update(updated)
            if let oldAlias = original.aliases.first, oldAlias != primaryAlias {
                tagsStore.remove(alias: oldAlias)
                if bypassStore.isBypassed(oldAlias) {
                    bypassStore.setBypassed(false, for: oldAlias)
                    bypassStore.setBypassed(true, for: primaryAlias)
                }
            }
            savedHost = updated
            isNew = false
        } else {
            let host = SSHHost(
                aliases: aliases,
                searchAliases: parsedSearchAliases,
                hostName: hostName.trimmed.nilIfEmpty,
                user: user.trimmed.nilIfEmpty,
                port: portValue,
                identityFile: identityFile.trimmed.nilIfEmpty,
                proxyJump: proxyJump.trimmed.nilIfEmpty,
                alternateUsers: parsedAlternateUsers,
                localForwards: parsedLocalForwards,
                remoteForwards: parsedRemoteForwards,
                remoteApp: remoteAppName,
                vncPort: parsedVNCPort
            )
            store.add(host)
            savedHost = host
            isNew = true
        }
        tagsStore.set(tag, for: primaryAlias)
        onSaved?(savedHost, isNew, addedAlternateUsers)
        dismiss()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// A mutable, identifiable row in the Port Forwarding editor. The forward is
/// split into its three editable parts (bind port / host / host port) plus a
/// direction and note, so a single list can hold both `-L` and `-R` entries; on
/// save it's joined into a `port:host:hostport` spec and split back into
/// `localForwards`/`remoteForwards`.
private struct ForwardDraft: Identifiable {
    enum Direction: Hashable { case local, remote }
    let id = UUID()
    var direction: Direction
    var bindPort: String
    var host: String
    var hostPort: String
    var note: String

    init(
        direction: Direction,
        bindPort: String = "",
        host: String = "",
        hostPort: String = "",
        note: String = ""
    ) {
        self.direction = direction
        self.bindPort = bindPort
        self.host = host
        self.hostPort = hostPort
        self.note = note
    }

    /// Splits a stored `[bind:]port:host:hostport` spec into the editable fields.
    /// The host and host-port are taken from the end (always present); anything
    /// before them becomes the bind/listen port.
    init(direction: Direction, parsing spec: String, note: String) {
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3 {
            self.init(
                direction: direction,
                bindPort: parts[0..<(parts.count - 2)].joined(separator: ":"),
                host: parts[parts.count - 2],
                hostPort: parts[parts.count - 1],
                note: note
            )
        } else {
            self.init(
                direction: direction,
                bindPort: parts.first ?? "",
                host: parts.count > 1 ? parts[1] : "",
                hostPort: "",
                note: note
            )
        }
    }
}
