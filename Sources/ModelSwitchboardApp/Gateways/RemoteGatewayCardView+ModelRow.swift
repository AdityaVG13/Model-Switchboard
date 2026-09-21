import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    func runningModelRow(_ status: ModelProfileStatus, metrics: HostMetricsPayload?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(status.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let rate = HostMetricsPresentation.servingRateLabel(status) {
                    Text(rate)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(accent)
                }
                Text(HostMetricsPresentation.profileMemoryLabel(
                    status: status,
                    metrics: metrics,
                    isRunning: true
                ) ?? "- · :" + status.port)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.sub)
            }
            if let procName = RemoteHostsPresentation.gpuProcessName(for: status, metrics: metrics) {
                Text(procName)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 2)
            }
        }
    }
}
