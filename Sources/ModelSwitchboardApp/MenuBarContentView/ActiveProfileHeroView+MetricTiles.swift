import SwiftUI
import ModelSwitchboardCore

extension ActiveProfileHeroView {
    @ViewBuilder
    func tokPerSecondTile(_ tok: Double) -> some View {
        Text(String(format: "%.1f", tok))
            .font(.system(size: 20, weight: .bold).monospacedDigit())
            .foregroundStyle(accent)
        Text("t/s")
            .font(.system(size: 10))
            .foregroundStyle(theme.sub)
    }

    func ttftTile(_ ttft: Double) -> some View {
        Text(String(format: "%.0f ms", ttft))
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(theme.sub)
            .accessibilityLabel("TTFT \(Int(ttft.rounded())) milliseconds")
    }

    @ViewBuilder
    func vramPercentTile(_ pct: Double) -> some View {
        Text("\(Int(pct.rounded()))%")
            .font(.system(size: 20, weight: .bold).monospacedDigit())
            .foregroundStyle(accent)
        Text("VRAM")
            .font(.system(size: 10))
            .foregroundStyle(theme.sub)
        if let detail = HostMetricsPresentation.hostVRAMUsedTotalLabel(hostMetrics) {
            Text(detail)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(theme.sub)
        }
    }
}
