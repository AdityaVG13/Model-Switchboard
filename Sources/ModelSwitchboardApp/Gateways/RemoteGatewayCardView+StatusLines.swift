import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    @ViewBuilder
    func statusLines(agentStale: Bool, metrics: HostMetricsPayload?) -> some View {
        if let message = runtime.forceUpdatePhase.failureMessage {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(DashboardTheme.stopRed)
                .fixedSize(horizontal: false, vertical: true)
        } else if let step = runtime.forceUpdatePhase.updatingStep {
            Text(step)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        } else if agentStale, !entry.unsupported {
            Text(GatewayConnectionBadge.help(
                for: runtime,
                agentStale: true,
                remoteVersion: metrics?.agentVersion
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(DashboardTheme.pendingOrange)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
