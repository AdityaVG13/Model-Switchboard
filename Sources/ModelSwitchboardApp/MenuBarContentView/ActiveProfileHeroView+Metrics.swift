import SwiftUI
import ModelSwitchboardCore

extension ActiveProfileHeroView {
    @ViewBuilder
    var localTrailingMetrics: some View {
        if let tok = decodeTokensPerSecond {
            tokPerSecondTile(tok)
        }
        if let ttft = ttftMilliseconds {
            ttftTile(ttft)
        }
    }

    @ViewBuilder
    var remoteTrailingMetrics: some View {
        if let pct = HostMetricsPresentation.hostVRAMPercent(hostMetrics) {
            vramPercentTile(pct)
        }
        if let bench = compactRemoteBenchLabel {
            Text(bench)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(theme.sub)
                .accessibilityLabel("Benchmark \(bench)")
        }
    }

    var compactRemoteBenchLabel: String? {
        var parts: [String] = []
        if let tok = decodeTokensPerSecond {
            parts.append(String(format: "%.1f t/s", tok))
        }
        if let ttft = ttftMilliseconds {
            parts.append(String(format: "%.0f ms", ttft))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
