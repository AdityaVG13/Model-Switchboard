import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    func appendThroughputParts(to parts: inout [String]) {
        if let serving = HostMetricsPresentation.servingRateLabel(profile) {
            parts.append(serving)
            return
        }
        appendBenchmarkThroughput(to: &parts)
    }

    func appendBenchmarkThroughput(to parts: inout [String]) {
        let benchRows = store.benchmark?.latest?.rows.filter { $0.profile == profile.profile } ?? []
        if let tok = benchRows.compactMap(\.decodeTokensPerSec).max() {
            parts.append(String(format: "%.1f t/s", tok))
        }
        if let ttft = bestBenchmarkTTFT(benchRows) {
            parts.append(String(format: "%.0f ms", ttft))
        }
    }

    func bestBenchmarkTTFT(_ benchRows: [BenchmarkLatestRow]) -> Double? {
        benchRows
            .max(by: { ($0.decodeTokensPerSec ?? -1) < ($1.decodeTokensPerSec ?? -1) })?
            .ttftMS
    }
}
