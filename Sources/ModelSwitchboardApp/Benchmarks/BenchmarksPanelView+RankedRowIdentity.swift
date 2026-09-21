import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func rankedRowIdentity(_ row: BenchmarkLatestRow, gatewayLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(BenchmarkMetricFormatting.benchmarkName(row))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.label)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 4) {
                if let gatewayLabel {
                    Text(gatewayLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.85))
                        .lineLimit(1)
                }
                if let runtime = row.runtime {
                    Text(gatewayLabel == nil ? runtime : ("· " + runtime))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
