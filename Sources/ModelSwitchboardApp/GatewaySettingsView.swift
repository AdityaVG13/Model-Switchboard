import SwiftUI
import ModelSwitchboardCore

/// Settings group for remote gateways: list, connection state, and an inline
/// add/edit form (the settings panel is a side panel, so no sheets).
struct GatewaySettingsSection: View {
    @Bindable var hub: GatewayHub
    let theme: DashboardTheme
    let accent: Color

    enum DeployState: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    static let installOneLiner =
        "curl -fsSL https://raw.githubusercontent.com/AdityaVG13/Model-Switchboard/main/RemoteAgent/install-remote-agent.sh | bash"

    @State private var draft: GatewayConfig?
    @State private var draftToken = ""
    @State private var draftIsNew = false
    @State private var linkCode = ""
    @State private var validationMessage: String?
    @State private var deployState: DeployState = .idle
    @State private var deployWithTailscale = false

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
            if draftIsNew {
                VStack(alignment: .leading, spacing: 4) {
                    field(
                        "Link code (optional)",
                        text: $linkCode,
                        prompt: "modelswitchboard-gateway://…",
                        monospaced: true
                    )
                    Text("Run `model-switchboard-agent link` on the remote host — it scans for existing model .env files, lets you confirm or paste a folder path, then prints a pairing code.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: linkCode) { _, newValue in
                    guard var parsed = GatewayLinkCode.parse(newValue) else { return }
                    if let existing = draft {
                        parsed.id = existing.id
                    }
                    draft = parsed
                    validationMessage = nil
                }
            }

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

                deploySection(config: binding.wrappedValue)
            case .direct:
                field("Controller URL", text: binding.baseURL, prompt: "http://spark.tail1234.ts.net:8877", monospaced: true)
                Text("The agent must be reachable at this URL. Tailscale is the easy path: run the agent with --tailscale (token required by default; paste the installer-generated token here). Plain LAN binds require --unsafe-bind plus a bearer token.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            deployStatusText

            if !draftIsNew, let runtime = hub.remoteRuntimes.first(where: { $0.id == config.id }),
               let profilesDirectory = runtime.store.profilesDirectory,
               !profilesDirectory.isEmpty
            {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profiles folder (on host)")
                        .font(.system(size: 12.5))
                    Text(profilesDirectory)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(theme.sub)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bearer token")
                    .font(.system(size: 12.5))
                SecureField(
                    tokenFieldPrompt,
                    text: $draftToken
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                Text(tokenFieldHelp)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var hasStoredToken: Bool {
        guard let id = draft?.id else { return false }
        return !hub.authToken(forGateway: id).isEmpty
    }

    private var tokenFieldPrompt: String {
        if draftIsNew || !hasStoredToken || !draftToken.isEmpty {
            return "Paste token — stored in keychain"
        }
        return "••••••••  leave blank to keep saved token"
    }

    private var tokenFieldHelp: String {
        if hasStoredToken, draftToken.isEmpty, !draftIsNew {
            return "A token is already saved in the keychain for this gateway. Leave blank to keep it, or paste a new one to replace it."
        }
        return "Required for Tailscale/direct agents with auth. Saved once in the keychain — you should not need to re-paste after relaunch."
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
            if config.hasUnsafeSSHDestination {
                validationMessage = "SSH user/host cannot start with '-' (would be parsed as an ssh option)."
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

    // MARK: - Agent deployment

    @ViewBuilder
    private func deploySection(config: GatewayConfig) -> some View {
        let sshReady = !config.sshHost.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                deployButton(
                    deployState == .running ? "Installing Agent…" : "Install Agent on Host",
                    prominent: true,
                    disabled: !sshReady || deployState == .running
                ) {
                    deployAgent(config: config)
                }
                deployButton("Copy Install One-Liner", prominent: false, disabled: false) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installOneLiner, forType: .string)
                }
            }
            Toggle(isOn: $deployWithTailscale) {
                Text("Bind the host's Tailscale address (tunnel-less direct mode)")
                    .font(.system(size: 10.5))
            }
            .toggleStyle(.checkbox)
            .disabled(deployState == .running)
            if deployState == .idle {
                Text("Nothing to install on the remote by hand: this pushes the single-file agent over SSH and sets up its service. With Tailscale mode, this gateway is converted to a direct tailnet connection after install. Or copy the one-liner to run there yourself.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Filled buttons (matching the dashboard's row-action style) so the
    /// primary install action reads clearly apart from the copy helper.
    private func deployButton(
        _ title: String,
        prominent: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    prominent ? accent.opacity(0.18) : theme.btnBg,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .foregroundStyle(prominent ? accent : theme.btnFg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    /// Rendered outside the SSH-only controls so a Tailscale install that
    /// converts the gateway to direct-URL kind keeps its status visible.
    @ViewBuilder
    private var deployStatusText: some View {
        switch deployState {
        case .idle:
            EmptyView()
        case .running:
            Text("Pushing the agent and running the installer over SSH…")
                .font(.system(size: 10))
                .foregroundStyle(DashboardTheme.pendingOrange)
        case .success(let message):
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(DashboardTheme.runningGreen)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let message):
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(DashboardTheme.stopRed)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deployAgent(config: GatewayConfig) {
        deployState = .running
        Task {
            let deployer = RemoteAgentDeployer()
            do {
                let result = try await deployer.deploy(to: config, useTailscale: deployWithTailscale)
                if deployWithTailscale,
                   let link = result.pairingLink,
                   var direct = GatewayLinkCode.parse(link),
                   direct.kind == .direct {
                    // Adopt the tailnet address the host reported; keep the
                    // user's id and any name they already typed.
                    direct.id = config.id
                    if !config.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        direct.name = config.name
                    }
                    draft = direct
                    deployState = .success(
                        "Agent installed in Tailscale mode — gateway switched to direct URL \(direct.baseURL). Save to connect."
                    )
                    return
                }
                let suffix = result.pairingLink == nil
                    ? "" : " The host printed its pairing code, so the connection details check out."
                deployState = .success("Agent installed on \(config.sshHost).\(suffix) Save the gateway to connect.")
            } catch let error as RemoteAgentDeployer.DeployError {
                switch error {
                case .missingResources:
                    deployState = .failure("This build is missing the bundled agent. Reinstall the app, or use the one-liner instead.")
                case .sshFailed(let step, let message):
                    deployState = .failure("Install failed while trying to \(step): \(message)")
                }
            } catch {
                deployState = .failure("Install failed: \(error.localizedDescription)")
            }
        }
    }

    private func closeEditor() {
        draft = nil
        draftToken = ""
        draftIsNew = false
        linkCode = ""
        validationMessage = nil
        deployState = .idle
        deployWithTailscale = false
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
