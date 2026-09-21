import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    @ViewBuilder
    func metricsBlock(primaryGPU: HostGPUMetrics?, metrics: HostMetricsPayload?) -> some View {
        if let error = entry.error, metrics == nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardTheme.stopRed.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if entry.unsupported {
                    Text(RemoteHostsPresentation.agentUpgradeHint(for: runtime))
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    copyInstallCommandRow
                }
            }
        } else {
            metricsTiles(primaryGPU: primaryGPU, metrics: metrics)
            metricsDetails(primaryGPU: primaryGPU, metrics: metrics)
        }
    }
}
