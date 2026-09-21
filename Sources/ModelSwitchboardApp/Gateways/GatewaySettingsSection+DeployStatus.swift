import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    /// Rendered outside the SSH-only controls so a Tailscale install that
    /// converts the gateway to direct-URL kind keeps its status visible.
    @ViewBuilder
    var deployStatusText: some View {
        switch deployState {
        case .idle:
            EmptyView()
        case .running:
            deployStatusLabel(
                "Pushing the agent and running the installer over SSH…",
                color: DashboardTheme.pendingOrange
            )
        case .success(let message):
            deployStatusLabel(message, color: DashboardTheme.runningGreen)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let message):
            deployStatusLabel(message, color: DashboardTheme.stopRed)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
