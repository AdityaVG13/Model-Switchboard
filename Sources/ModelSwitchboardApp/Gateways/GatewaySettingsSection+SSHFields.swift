import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @ViewBuilder
    func sshFields(_ binding: Binding<GatewayConfig>) -> some View {
        field("SSH user", text: GatewayConnectionField.ssh(binding, \.sshUser, fallback: ""), prompt: NSUserName(), monospaced: true)
        field("SSH host", text: GatewayConnectionField.ssh(binding, \.sshHost, fallback: ""), prompt: "box.local or lab-gpu", monospaced: true)
        HStack(spacing: 10) {
            numberField("SSH port", value: GatewayConnectionField.ssh(binding, \.sshPort, fallback: 0))
            numberField("Agent port", value: GatewayConnectionField.ssh(binding, \.remotePort, fallback: 0))
        }
        field(
            "Identity file (optional)",
            text: SettingsChrome.optionalString(GatewayConnectionField.ssh(binding, \.identityFile, fallback: nil)),
            prompt: "~/.ssh/id_ed25519",
            monospaced: true
        )
        Text("Uses your SSH keys and agent (BatchMode) - passwords are never handled. Connect once from Terminal first so the host key is trusted.")
            .font(.system(size: 10))
            .foregroundStyle(theme.sub)
            .fixedSize(horizontal: false, vertical: true)

        deploySection(config: binding.wrappedValue)
    }

    @ViewBuilder
    func directFields(_ binding: Binding<GatewayConfig>) -> some View {
        field("Controller URL", text: GatewayConnectionField.direct(binding, \.baseURL, fallback: ""), prompt: "http://host.example.ts.net:8877", monospaced: true)
        Text("The agent must be reachable at this URL. Tailscale is the easy path: run the agent with --tailscale (token required by default; paste the installer-generated token here). Plain LAN binds require --unsafe-bind plus a bearer token.")
            .font(.system(size: 10))
            .foregroundStyle(theme.sub)
            .fixedSize(horizontal: false, vertical: true)
        field("Deploy host (optional)", text: SettingsChrome.optionalString(GatewayConnectionField.direct(binding, \.deployHost, fallback: nil)), prompt: "ssh alias, e.g. gpu", monospaced: true)
        Text("Used only by Update to push the agent over SSH. Defaults to the URL host - which hangs when that host needs Tailscale SSH re-auth. Use an ssh-config alias or a tailnet destination such as `user@100.64.1.2`.")
            .font(.system(size: 10))
            .foregroundStyle(theme.sub)
            .fixedSize(horizontal: false, vertical: true)
    }
}
