import SwiftUI
import ModelSwitchboardCore

extension GatewayConnectionBadge {
    @MainActor
    static func updateActionTitle(for runtime: GatewayRuntime, agentStale: Bool = false) -> String {
        switch runtime.forceUpdatePhase {
        case .updating:
            return "Updating…"
        case .failed:
            return "Retry"
        case .idle:
            return agentStale ? "Update agent" : "Update"
        }
    }

    @MainActor
    static func updateActionColor(
        for runtime: GatewayRuntime,
        agentStale: Bool = false,
        theme: DashboardTheme,
        accent: Color
    ) -> Color {
        switch runtime.forceUpdatePhase {
        case .updating:
            return accent
        case .failed:
            return DashboardTheme.stopRed
        case .idle:
            return agentStale ? DashboardTheme.pendingOrange : theme.faint
        }
    }
}
