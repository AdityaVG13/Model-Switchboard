import AppKit
import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @ViewBuilder
    func deploySection(config: GatewayConfig) -> some View {
        let sshReady = isSSHDeployReady(config)
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
                Text("Nothing to install on the remote by hand: this pushes the bundled agent over SSH and sets up its service. With Tailscale mode, this gateway is converted to a direct tailnet connection after install. Or copy the one-liner to run there yourself.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
