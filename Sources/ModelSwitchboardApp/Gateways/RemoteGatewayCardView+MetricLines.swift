import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    @ViewBuilder
    func storageLine(_ metrics: HostMetricsPayload?) -> some View {
        if let storage = HostMetricsPresentation.storageLabel(metrics) {
            Text("STORAGE \(storage)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(theme.sub)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    func networkLine(_ metrics: HostMetricsPayload?) -> some View {
        if let network = HostMetricsPresentation.networkLabel(metrics) {
            Text(network)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(theme.sub)
                .lineLimit(1)
        }
    }
}
