import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func suiteLine(latest: BenchmarkLatestReport, best: BenchmarkLatestRow?, gatewayLabel: String?) -> String {
        let suite = BenchmarkMetricFormatting.suiteLabel(latest.suite).lowercased()
        let runtime = best?.runtime ?? "-"
        if let gatewayLabel {
            return "suite " + suite + " · " + runtime + " · " + gatewayLabel
        }
        return "suite " + suite + " · " + runtime
    }

    func gigabytes(_ megabytes: Double?) -> String {
        guard let megabytes else { return "\u{2014}" }
        return String(format: "%.1f", megabytes / 1024)
    }

    func latestRunLabel(_ generatedAt: String?) -> String {
        guard let date = Self.parsedGeneratedAt(generatedAt) else { return "LATEST RUN" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "LATEST RUN \u{00b7} \(formatter.string(from: date).uppercased())"
    }

    static func formattedGeneratedAt(_ value: String?) -> String {
        BenchmarkTimestampFormatting.formattedGeneratedAt(value)
    }

    static func parsedGeneratedAt(_ value: String?) -> Date? {
        BenchmarkTimestampFormatting.parsedGeneratedAt(value)
    }
}
