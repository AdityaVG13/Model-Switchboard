import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    func nameRow(metrics: HostMetricsPayload?) -> some View {
        HStack(spacing: 4) {
            Text(runtime.name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(theme.label)
                .lineLimit(1)
            if let uptime = HostMetricsPresentation.uptimeLabel(metrics) {
                Text(uptime)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.faint)
            }
            Button {
                renamingGatewayID = runtime.id
                renameDraft = runtime.name
                renameError = nil
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietCraftPressStyle())
            .help("Rename this gateway")
            .accessibilityLabel("Rename " + runtime.name)
        }
    }
}
