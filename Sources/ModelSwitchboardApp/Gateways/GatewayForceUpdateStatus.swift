import SwiftUI

/// Shared force-update progress line used by the settings list and editor.
struct GatewayForceUpdateStatus: View {
    let phase: GatewayForceUpdatePhase
    let theme: DashboardTheme

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .failed(let message):
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(DashboardTheme.stopRed)
                .fixedSize(horizontal: false, vertical: true)
        case .updating(let step):
            Text(step)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
