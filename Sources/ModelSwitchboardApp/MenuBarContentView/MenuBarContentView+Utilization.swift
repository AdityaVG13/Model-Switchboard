import SwiftUI

extension MenuBarContentView {
    var utilizationGrid: some View {
        HStack(spacing: 6) {
            utilizationCell(label: "CPU", value: systemMetrics.cpuUsagePercent, history: systemMetrics.cpuHistory)
            utilizationCell(label: "RAM", value: systemMetrics.memoryUsagePercent, history: systemMetrics.memoryHistory)
            utilizationCell(label: "GPU", value: systemMetrics.gpuUsagePercent, history: systemMetrics.gpuHistory)
        }
    }
}
