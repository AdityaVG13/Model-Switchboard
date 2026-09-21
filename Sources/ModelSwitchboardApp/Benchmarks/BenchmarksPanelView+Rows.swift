import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func summaryCard(_ latest: BenchmarkLatestReport, gatewayLabel: String?) -> some View {
        let best = BenchmarkMetricFormatting.sortedRowsForDisplay(latest.rows).first

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(latestRunLabel(latest.generatedAt))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(theme.faint)
                Text(BenchmarkMetricFormatting.benchmarkName(best))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(suiteLine(latest: latest, best: best, gatewayLabel: gatewayLabel))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.sub)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                metricColumn(BenchmarkMetricFormatting.tokensPerSecond(best?.decodeTokensPerSec), unit: "decode t/s", emphasized: true)
                metricColumn(BenchmarkMetricFormatting.tokensPerSecond(best?.e2eTokensPerSec), unit: "e2e t/s")
                metricColumn(BenchmarkMetricFormatting.milliseconds(best?.ttftMS), unit: "TTFT ms")
                metricColumn(gigabytes(best?.rssMB), unit: "RSS GB")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }
}
