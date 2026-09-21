import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    func metricsTiles(primaryGPU: HostGPUMetrics?, metrics: HostMetricsPayload?) -> some View {
        HStack(spacing: 6) {
            metricTile(
                label: "CPU",
                value: HostMetricsPresentation.percentLabel(metrics?.cpuPercent),
                detail: nil
            )
            metricTile(
                label: "RAM",
                value: HostMetricsPresentation.percentLabel(metrics?.memory?.percent),
                detail: RemoteHostsPresentation.memoryDetail(metrics?.memory)
            )
            metricTile(
                label: "GPU",
                value: HostMetricsPresentation.percentLabel(primaryGPU?.utilPercent),
                detail: primaryGPU?.tempC.map { String(format: "%.0f°C", $0) }
            )
            metricTile(
                label: "VRAM",
                value: HostMetricsPresentation.percentLabel(
                    HostMetricsPresentation.hostVRAMPercent(metrics)
                ),
                detail: HostMetricsPresentation.hostVRAMUsedTotalLabel(metrics)
            )
        }
    }

    @ViewBuilder
    func metricsDetails(primaryGPU: HostGPUMetrics?, metrics: HostMetricsPayload?) -> some View {
        storageLine(metrics)
        networkLine(metrics)
        tailnetRow(metrics)
        gpuLines(primaryGPU: primaryGPU, metrics: metrics)
        pollErrorLine
    }
}
