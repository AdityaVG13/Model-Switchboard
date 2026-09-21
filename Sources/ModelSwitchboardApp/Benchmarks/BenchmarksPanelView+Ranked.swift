import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func rankedRows(_ latest: BenchmarkLatestReport, gatewayLabel: String?) -> some View {
        let rows = BenchmarkMetricFormatting.sortedRowsForDisplay(latest.rows)
        let maxDecode = max(rows.compactMap(\.decodeTokensPerSec).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 0) {
            Text("ALL MODELS \u{00b7} BEST DECODE")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.faint)
                .padding(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                rankedRow(row, isTop: index == 0, maxDecode: maxDecode, gatewayLabel: gatewayLabel)
            }
        }
        .padding(.horizontal, 10)
    }
}
