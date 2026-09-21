import AppKit
import SwiftUI
import ModelSwitchboardCore

struct RemoteGatewayCardView: View {
    @Bindable var hub: GatewayHub
    @Bindable var metricsMonitor: RemoteHostMetricsMonitor
    let runtime: GatewayRuntime
    let entry: RemoteHostMetricsMonitor.Entry
    let theme: DashboardTheme
    let accent: Color
    @Binding var renamingGatewayID: String?
    @Binding var renameDraft: String
    @Binding var renameError: String?
    @Binding var didCopyInstallCommand: Bool
    let hideHostInfo: Bool

    var body: some View {
        let metrics = entry.metrics
        let primaryGPU = metrics?.gpus.first
        let agentStale = RemoteAgentVersion.isRemoteStale(
            metrics: metrics,
            unsupported: entry.unsupported
        )

        return VStack(alignment: .leading, spacing: 10) {
            header(agentStale: agentStale, metrics: metrics)
            statusLines(agentStale: agentStale, metrics: metrics)
            metricsBlock(primaryGPU: primaryGPU, metrics: metrics)
            runningModels(metrics: metrics)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }
}
