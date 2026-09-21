import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    var headerDot: some View {
        Circle()
            .fill(RemoteHostsPresentation.statusColor(
                runtime: runtime,
                entry: entry,
                dotOff: theme.dotOff
            ))
            .frame(width: 7, height: 7)
    }

    func headerIdentity(metrics: HostMetricsPayload?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if renamingGatewayID == runtime.id {
                renameEditor
            } else {
                nameRow(metrics: metrics)
            }
            if let renameError, renamingGatewayID == runtime.id {
                Text(renameError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.stopRed)
            }
            Text(RemoteHostsPresentation.subtitle(
                runtime: runtime,
                metrics: metrics,
                hideHostInfo: hideHostInfo
            ))
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(theme.sub)
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }
}
