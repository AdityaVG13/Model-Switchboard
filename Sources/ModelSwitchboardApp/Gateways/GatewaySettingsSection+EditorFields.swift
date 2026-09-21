import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @ViewBuilder
    func existingGatewayActions(_ runtime: GatewayRuntime) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            linkButton(
                GatewayConnectionBadge.updateActionTitle(for: runtime),
                emphasized: true
            ) {
                Task { await hub.forceUpdateGateway(id: runtime.id) }
            }
            .disabled(runtime.forceUpdatePhase.isUpdating)
            Text("Pushes the agent bundled in this app over SSH, then refreshes models and ports on this host.")
                .font(.system(size: 10))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            GatewayForceUpdateStatus(phase: runtime.forceUpdatePhase, theme: theme)
        }

        existingGatewayProfiles(runtime)
    }
}
