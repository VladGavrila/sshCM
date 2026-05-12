import SwiftUI

struct AddHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var store
    @Environment(TagsStore.self) private var tagsStore

    let editing: SSHHost?
    var onAdded: ((SSHHost) -> Void)?

    @State private var alias: String
    @State private var hostName: String
    @State private var user: String
    @State private var portText: String
    @State private var showAdvanced: Bool
    @State private var identityFile: String
    @State private var proxyJump: String
    @State private var tag: HostTag?
    @State private var showTagPicker: Bool = false

    init(editing: SSHHost? = nil, onAdded: ((SSHHost) -> Void)? = nil) {
        self.editing = editing
        self.onAdded = onAdded
        let initialAlias = editing?.aliases.joined(separator: " ") ?? ""
        let initialHostName = editing?.hostName ?? ""
        let initialUser = editing?.user ?? ""
        let initialPort = editing.flatMap { $0.port.map(String.init) } ?? "22"
        let initialIdentity = editing?.identityFile ?? ""
        let initialProxy = editing?.proxyJump ?? ""
        let hasAdvanced = !initialIdentity.isEmpty || !initialProxy.isEmpty

        _alias = State(initialValue: initialAlias)
        _hostName = State(initialValue: initialHostName)
        _user = State(initialValue: initialUser)
        _portText = State(initialValue: initialPort)
        _identityFile = State(initialValue: initialIdentity)
        _proxyJump = State(initialValue: initialProxy)
        _showAdvanced = State(initialValue: hasAdvanced)
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
        && !hostName.trimmed.isEmpty
        && !user.trimmed.isEmpty
        && portIsValid
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Host") {
                    HStack(spacing: 8) {
                        TextField("Alias", text: $alias, prompt: Text("e.g. prod-bastion"))
                        tagButton
                    }
                    TextField("HostName (IP or FQDN)", text: $hostName, prompt: Text("e.g. 10.0.0.4 or db.example.com"))
                    TextField("User", text: $user, prompt: Text("e.g. ubuntu"))
                    TextField("Port", text: $portText)
                    if !portIsValid {
                        Text("Port must be between 1 and 65535.")
                            .font(.caption)
                            .foregroundStyle(.red)
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
                        }
                        .padding(.top, 4)
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
        .frame(minWidth: 460, minHeight: 300)
        .animation(.easeInOut(duration: 0.25), value: showAdvanced)
        .onAppear(perform: loadExistingTag)
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
        let aliases = alias.trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !aliases.isEmpty else { return }
        let primaryAlias = aliases[0]
        if let original = editing {
            var updated = original
            updated.aliases = aliases
            updated.hostName = hostName.trimmed.nilIfEmpty
            updated.user = user.trimmed.nilIfEmpty
            updated.port = portValue
            updated.identityFile = identityFile.trimmed.nilIfEmpty
            updated.proxyJump = proxyJump.trimmed.nilIfEmpty
            store.update(updated)
            if let oldAlias = original.aliases.first, oldAlias != primaryAlias {
                tagsStore.remove(alias: oldAlias)
            }
        } else {
            let host = SSHHost(
                aliases: aliases,
                hostName: hostName.trimmed.nilIfEmpty,
                user: user.trimmed.nilIfEmpty,
                port: portValue,
                identityFile: identityFile.trimmed.nilIfEmpty,
                proxyJump: proxyJump.trimmed.nilIfEmpty
            )
            store.add(host)
            onAdded?(host)
        }
        tagsStore.set(tag, for: primaryAlias)
        dismiss()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
