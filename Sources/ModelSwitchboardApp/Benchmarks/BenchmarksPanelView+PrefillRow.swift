import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func prefillRow(_ benchCase: BenchmarkPrefillCase, maxTTFT: Double) -> some View {
        let fraction = max(0, min(1, (benchCase.ttftMS ?? 0) / maxTTFT))

        return HStack(spacing: 10) {
            Text(benchCase.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.sub)
                .frame(width: 30, alignment: .leading)

            prefillBar(fraction: fraction)

            Text("\(BenchmarkMetricFormatting.milliseconds(benchCase.ttftMS)) ms")
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .foregroundStyle(theme.label)
                .frame(width: 62, alignment: .trailing)

            Text("\(BenchmarkMetricFormatting.tokensPerSecond(benchCase.decodeTokensPerSec)) t/s")
                .font(.system(size: 10, design: .monospaced).monospacedDigit())
                .foregroundStyle(theme.sub)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(benchCase.label) context: \(BenchmarkMetricFormatting.milliseconds(benchCase.ttftMS)) milliseconds to first token"
        )
    }
}
