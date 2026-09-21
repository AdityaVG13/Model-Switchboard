import Foundation
import ModelSwitchboardCore

extension BenchmarkCSVExport {
    static func makeCSV(from latest: BenchmarkLatestReport) -> String {
        var lines: [String] = []
        lines.append("suite,generated_at,profile,runtime,ttft_ms,decode_tps,e2e_tps,rss_mb")
        for row in latest.rows {
            lines.append([
                csvField(latest.suite ?? ""),
                csvField(latest.generatedAt ?? ""),
                csvField(row.profile ?? ""),
                csvField(row.runtime ?? ""),
                csvField(BenchmarkMetricFormatting.milliseconds(row.ttftMS)),
                csvField(BenchmarkMetricFormatting.tokensPerSecond(row.decodeTokensPerSec)),
                csvField(BenchmarkMetricFormatting.tokensPerSecond(row.e2eTokensPerSec)),
                csvField(BenchmarkMetricFormatting.megabytes(row.rssMB))
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
