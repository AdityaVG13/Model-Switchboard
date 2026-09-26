import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewaySectionView {
    var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                DashboardSectionLabel(
                    // U+2215 DIVISION SLASH: stays in the digit band, unlike "/".
                    text: "\(runtime.name.uppercased()) · \(store.displayedReadyProfiles)\u{2215}\(store.summary.totalProfiles) READY",
                    theme: theme
                )
                Spacer(minLength: 0)
                GatewayForceUpdateControls(
                    runtime: runtime,
                    agentStale: agentStale,
                    remoteVersion: hostMetrics?.agentVersion,
                    theme: theme,
                    accent: accent,
                    onUpdate: { onForceUpdate?() }
                )
                .disabled(onForceUpdate == nil)
            }
            forceUpdateStatus
            if let chip = HostMetricsPresentation.sectionMetricsChip(hostMetrics) {
                Text(chip)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.9))
                    .lineLimit(1)
                    .padding(.leading, 12)
                    .accessibilityLabel("Host GPU metrics: \(chip)")
            }
        }
        .padding(EdgeInsets(top: 10, leading: 4, bottom: 4, trailing: 4))
    }
}
