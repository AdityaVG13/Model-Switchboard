import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func displayNameField(_ binding: Binding<GatewayConfig>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            field("Display name", text: binding.name, prompt: "Lab GPU / home box")
            Text("Your label for this machine. Shown on the dashboard and Remote Hosts. Rename anytime.")
                .font(.system(size: 10))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func connectionFields(_ binding: Binding<GatewayConfig>) -> some View {
        switch binding.wrappedValue.connection {
        case .ssh:
            sshFields(binding)
        case .direct:
            directFields(binding)
        }
    }
}
