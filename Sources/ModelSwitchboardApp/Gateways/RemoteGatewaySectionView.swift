import SwiftUI
import ModelSwitchboardCore

/// One remote gateway's header plus its model rows, visually matching the
/// local standby list.
struct RemoteGatewaySectionView: View {
    @Bindable var runtime: GatewayRuntime
    let filter: MenuBarContentView.ProfileFilter
    /// Profile ids already shown in ACTIVE ON hero cards for this gateway.
    var excludeProfileIDs: Set<String> = []
    /// Live host metrics from GET /api/host/metrics (GPU/VRAM), not process RSS.
    var hostMetrics: HostMetricsPayload? = nil
    /// Host agent is older than the agent bundled in this Mac app.
    var agentStale: Bool = false
    var onForceUpdate: (() -> Void)? = nil
    let theme: DashboardTheme
    let accent: Color
    var onOpenBenchmarks: (() -> Void)? = nil

    var store: SwitchboardStore { runtime.store }

    var body: some View {
        // Header-only sections (hero stole the only row, or filter miss) are
        // noise -- keep the section only when there are rows, a real empty
        // profiles directory, or a connection issue to surface.
        // Keep the gateway chrome when heroes stole every row so DIRECT/SSH
        // badges and ready counts do not vanish on an all-running remote.
        if shouldShowSection {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader
                connectionIssueLabel
                profileRows
            }
            .padding(EdgeInsets(top: 0, leading: 10, bottom: 6, trailing: 10))
        }
    }
}
