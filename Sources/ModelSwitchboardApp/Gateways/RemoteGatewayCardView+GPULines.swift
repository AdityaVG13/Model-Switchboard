import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    @ViewBuilder
    func gpuLines(primaryGPU: HostGPUMetrics?, metrics: HostMetricsPayload?) -> some View {
        if let gpus = metrics?.gpus, gpus.count > 1 {
            ForEach(gpus) { gpu in
                Text(RemoteHostsPresentation.gpuLine(gpu))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.sub)
                    .lineLimit(1)
            }
        } else if let gpu = primaryGPU, let name = gpu.name, !name.isEmpty {
            Text(name)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.sub)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    var pollErrorLine: some View {
        if let error = entry.error, entry.unsupported == false {
            Text(error)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.faint)
                .lineLimit(2)
        }
    }
}
