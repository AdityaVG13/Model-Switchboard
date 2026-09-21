import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func rankedRow(_ row: BenchmarkLatestRow, isTop: Bool, maxDecode: Double, gatewayLabel: String?) -> some View {
        let fraction = max(0, min(1, (row.decodeTokensPerSec ?? 0) / maxDecode))

        return HStack(spacing: 10) {
            rankedRowIdentity(row, gatewayLabel: gatewayLabel)
            rankedRowBar(fraction: fraction, isTop: isTop)
            Text("\(BenchmarkMetricFormatting.tokensPerSecond(row.decodeTokensPerSec)) t/s")
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .foregroundStyle(theme.label)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6))
    }
}
