import SwiftUI
import ModelSwitchboardCore

/// Status chip plus a separate Update button so DIRECT/SSH is not the action.
struct GatewayForceUpdateControls: View {
    @Bindable var runtime: GatewayRuntime
    var agentStale: Bool = false
    var remoteVersion: String? = nil
    let theme: DashboardTheme
    let accent: Color
    var capsuleUpdate: Bool = false
    var onUpdate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            statusLabel
            updateButton
        }
    }
}
