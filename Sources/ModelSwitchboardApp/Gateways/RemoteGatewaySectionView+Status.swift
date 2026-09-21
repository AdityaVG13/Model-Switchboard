import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewaySectionView {
    @ViewBuilder
    var forceUpdateStatus: some View {
        if let message = runtime.forceUpdatePhase.failureMessage {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(DashboardTheme.stopRed)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
        } else if let step = runtime.forceUpdatePhase.updatingStep {
            Text(step)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
        }
    }

    var statusColor: Color {
        if runtime.tunnelState.isFailed { return DashboardTheme.stopRed }
        if runtime.tunnelState == .connecting { return DashboardTheme.pendingOrange }
        if store.lastError != nil { return DashboardTheme.stopRed }
        if store.displayedReadyProfiles > 0 { return DashboardTheme.runningGreen }
        // Fresh contact with the agent counts as online even with 0 models ready.
        if store.lastUpdated != nil, store.statusFreshness(relativeTo: .now) == .fresh {
            return DashboardTheme.runningGreen.opacity(0.55)
        }
        return theme.dotOff
    }

    var connectionIssue: String? {
        runtime.tunnelState.failureMessage ?? store.lastError
    }
}
