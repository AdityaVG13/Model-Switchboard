import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    @ViewBuilder
    func tailnetRow(_ metrics: HostMetricsPayload?) -> some View {
        if let tailnet = HostMetricsPresentation.tailnetLabel(metrics) {
            HStack(spacing: 4) {
                Circle()
                    .fill(RemoteHostsPresentation.tailnetDotColor(metrics: metrics))
                    .frame(width: 6, height: 6)
                Text(tailnet.label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(theme.sub)
                if let detail = tailnet.detail, !hideHostInfo {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}
