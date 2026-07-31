import SwiftUI
import ModelSwitchboardCore

/// Settings group for remote gateways: list, connection state, and an inline
/// add/edit form (the settings panel is a side panel, so no sheets).
struct GatewaySettingsSection: View {
    @Bindable var hub: GatewayHub
    let theme: DashboardTheme
    let accent: Color

    @State private var draft: GatewayConfig?
    @State private var draftToken = ""
    @State private var draftIsNew = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardSectionLabel(text: "REMOTE GATEWAYS", theme: theme)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 4))

            VStack(alignment: .leading, spacing: 0) {
                if hub.remoteRuntimes.isEmpty && draft == nil {
                    emptyState
                } else {
                    gatewayList
                }
                if let draft {
                    divider
                    editor(for: draft)
                } else {
                    divider
                    addButton
                }
            }
            .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 12)
    }

    // MARK: - List

    private var emptyState: some View {
        Text("Launch and monitor model servers on other machines — a DGX box, a Linux workstation, anything running the Model Switchboard agent. SSH tunnels use your existing keys; nothing else is stored.")
            .font(.system(size: 10.5))
            .foregroundStyle(theme.sub)
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
    }

    private var gatewayList: some View {
        ForEach(hub.remoteRuntimes) { runtime in
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(runtime))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(runtime.name)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(runtime.config.endpointSummary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                linkButton("Edit") {
                    draft = runtime.config
                    draftToken = hub.authToken(forGateway: runtime.id)
                    draftIsNew = false
                    validationMessage = nil
                }
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private func statusColor(_ runtime: GatewayRuntime) -> Color {
        if case .failed = runtime.tunnelState { return DashboardTheme.stopRed }
        if runtime.tunnelState == .connecting { return DashboardTheme.pendingOrange }
        if runtime.store.lastError != nil { return DashboardTheme.stopRed }
        if runtime.store.lastUpdated != nil { return DashboardTheme.runningGreen }
        return theme.dotOff
    }

    private var addButton: some View {
        linkButton("Add Remote Gateway…", emphasized: true) {
            draft = GatewayConfig(name: "", kind: .ssh)
            draftToken = ""
            draftIsNew = true
            validationMessage = nil
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(for config: GatewayConfig) -> some View {
        let binding = Binding(
            get: { draft ?? config },
            set: { draft = $0 }
        )
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: binding.name, prompt: "DGX Spark")

            HStack(spacing: 8) {
                Text("Connection")
                    .font(.system(size: 12.5))
                Picker("", selection: binding.kind) {
                    Text("SSH tunnel").tag(GatewayKind.ssh)
                    Text("Direct URL").tag(GatewayKind.direct)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch binding.wrappedValue.kind {
            case .ssh:
                field("SSH user", text: binding.sshUser, prompt: NSUserName(), monospaced: true)
                field("SSH host", text: binding.sshHost, prompt: "spark.local", monospaced: true)
                HStack(spacing: 10) {
                    numberField("SSH port", value: binding.sshPort)
                    numberField("Agent port", value: binding.remotePort)
                }
                field(
                    "Identity file (optional)",
                    text: optionalText(binding.identityFile),
                    prompt: "~/.ssh/id_ed25519",
                    monospaced: true
                )
                Text("Uses your SSH keys and agent (BatchMode) — passwords are never handled. Connect once from Terminal first so the host key is trusted.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            case .direct:
                field("Controller URL", text: binding.baseURL, prompt: "http://spark.local:8877", monospaced: true)
                Text("The agent must be reachable at this URL. Non-loopback agents require a bearer token (run the agent with --unsafe-bind and --auth-token-file).")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bearer token (optional)")
                    .font(.system(size: 12.5))
                SecureField("Stored in your keychain", text: $draftToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.stopRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                linkButton("Save", emphasized: true) { save() }
                linkButton("Cancel") { closeEditor() }
                Spacer()
                if !draftIsNew {
                    linkButton("Remove", color: DashboardTheme.stopRed) {
                        hub.removeGateway(id: config.id)
                        closeEditor()
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
    }

    private func save() {
        guard var config = draft else { return }
        config.name = config.name.trimmingCharacters(in: .whitespaces)
        config.baseURL = config.baseURL.trimmingCharacters(in: .whitespaces)
        config.sshHost = config.sshHost.trimmingCharacters(in: .whitespaces)
        config.sshUser = config.sshUser.trimmingCharacters(in: .whitespaces)

        if config.name.isEmpty {
            validationMessage = "Give this gateway a name."
            return
        }
        switch config.kind {
        case .ssh:
            if config.sshHost.isEmpty {
                validationMessage = "SSH host is required."
                return
            }
        case .direct:
            guard let url = URL(string: config.baseURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil
            else {
                validationMessage = "Controller URL must be an http(s) URL."
                return
            }
        }
        hub.upsertGateway(config, token: draftToken)
        closeEditor()
    }

    private func closeEditor() {
        draft = nil
        draftToken = ""
        draftIsNew = false
        validationMessage = nil
    }

    // MARK: - Small helpers (visually matching SettingsView)

    private var divider: some View {
        theme.line.frame(height: 1).padding(.horizontal, 10)
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
        }
    }

    private func numberField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
            TextField(
                "",
                text: Binding(
                    get: { String(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) ?? value.wrappedValue }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11.5, design: .monospaced))
            .frame(width: 90)
        }
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func linkButton(
        _ title: String,
        emphasized: Bool = false,
        color: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .semibold : .regular))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color ?? (emphasized ? accent : theme.btnFg))
    }
}
