import AppKit
import UniformTypeIdentifiers
import ModelSwitchboardCore

enum BenchmarkCSVExport {
    struct Notice: Equatable {
        let message: String
        let isError: Bool
    }

    static func defaultFileName(_ generatedAt: String?) -> String {
        let timestamp: String
        if let generatedAt, !generatedAt.isEmpty {
            let cleaned = generatedAt
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "T", with: "_")
                .replacingOccurrences(of: "Z", with: "")
            timestamp = cleaned
        } else {
            timestamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "T", with: "_")
                .replacingOccurrences(of: "Z", with: "")
        }
        return "model-switchboard-benchmark-\(timestamp).csv"
    }

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

    @MainActor
    static func presentSavePanel(
        for latest: BenchmarkLatestReport,
        onComplete: @escaping (Notice) -> Void
    ) {
        guard !latest.rows.isEmpty else {
            onComplete(Notice(message: "No benchmark data to export yet.", isError: true))
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Benchmark CSV"
        panel.prompt = "Export"
        panel.nameFieldStringValue = defaultFileName(latest.generatedAt)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        Task { @MainActor in
            let response = await panel.begin()
            guard response == .OK, let url = panel.url else { return }
            do {
                try makeCSV(from: latest).write(to: url, atomically: true, encoding: .utf8)
                onComplete(Notice(message: "Exported CSV to \(url.lastPathComponent).", isError: false))
            } catch {
                onComplete(Notice(message: "CSV export failed: \(error.localizedDescription)", isError: true))
            }
        }
    }

    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
