import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ModelSwitchboardCore

struct BenchmarksPanelView: View {
    let benchmark: BenchmarkStatus?
    let activeBenchmarkProfiles: [String]
    let cooldownEndsAt: Date?
    let runBenchmark: () -> Void
    @State private var exportNotice: ExportNotice?
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("Latest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                statusChip
                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    benchmarkActionButton
                    exportButton
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    benchmarkActionButton
                    exportButton
                }
            }

            if benchmark?.running == true {
                Text(activeRunLabel)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The table below shows the latest completed run until this benchmark finishes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let benchmarkCooldownLabel {
                Text("Benchmark cooldown: \(benchmarkCooldownLabel) remaining. You can still open this panel without rerunning.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let latest = benchmark?.latest {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suite: \(suiteLabel(latest.suite))")
                        .font(.footnote.weight(.semibold))
                    Text("Generated: \(formattedGeneratedAt(latest.generatedAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                metricsStrip(rows: latest.rows)
            } else {
                Text("No benchmark recorded yet. Run a benchmark to populate this panel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let exportNotice {
                Text(exportNotice.message)
                    .font(.caption2)
                    .foregroundStyle(exportNotice.isError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rows = benchmark?.latest?.rows, !rows.isEmpty {
                tableView(rows: rows)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
    }

    private var statusChip: some View {
        let running = benchmark?.running == true
        return Text(running ? "RUNNING" : "READY")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((running ? Color.orange : Color.green).opacity(0.18), in: Capsule())
            .foregroundStyle(running ? Color.orange : Color.green)
    }

    private func tableView(rows: [BenchmarkLatestRow]) -> some View {
        let displayRows = sortedRowsForDisplay(rows)
        let rowHeight: CGFloat = 32
        let maxTableHeight: CGFloat = 320
        let interRowSpacing: CGFloat = 4
        let contentPadding: CGFloat = 10
        let desiredHeight = min(
            maxTableHeight,
            max(
                rowHeight + contentPadding,
                CGFloat(displayRows.count) * rowHeight +
                    CGFloat(max(0, displayRows.count - 1)) * interRowSpacing +
                    contentPadding
            )
        )
        let comparisonHeight: CGFloat = displayRows.count > 1 ? 44 : 0

        return GeometryReader { proxy in
            let widths = columnWidths(totalWidth: max(220, proxy.size.width - 16))
            VStack(alignment: .leading, spacing: 8) {
                if displayRows.count > 1 {
                    comparisonStrip(rows: displayRows)
                }
                benchmarkHeader(widths)
                ScrollView(.vertical, showsIndicators: displayRows.count > 7) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(displayRows.enumerated()), id: \.offset) { index, row in
                            benchmarkRow(row, index: index, widths: widths)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: desiredHeight)
                .scrollIndicators(.visible)
            }
            .padding(8)
            .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(height: desiredHeight + 40 + comparisonHeight)
    }

    private func benchmarkHeader(_ widths: ColumnWidths) -> some View {
        HStack(spacing: 0) {
            headerCell("Profile", width: widths.profile, align: .center)
            tableDivider()
            headerCell("TTFT", width: widths.ttft, align: .center)
            tableDivider()
            headerCell("Decode", width: widths.decode, align: .center)
            tableDivider()
            headerCell("E2E", width: widths.e2e, align: .center)
            tableDivider()
            headerCell("RSS", width: widths.rss, align: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func benchmarkRow(_ row: BenchmarkLatestRow, index: Int, widths: ColumnWidths) -> some View {
        HStack(spacing: 0) {
            valueCell(compactProfileName(row.profile ?? row.runtime ?? "unknown"), width: widths.profile, align: .center)
            tableDivider()
            valueCell(ms(row.ttftMS), width: widths.ttft, align: .center)
            tableDivider()
            valueCell(tps(row.decodeTokensPerSec), width: widths.decode, align: .center)
            tableDivider()
            valueCell(tps(row.e2eTokensPerSec), width: widths.e2e, align: .center)
            tableDivider()
            valueCell(mb(row.rssMB), width: widths.rss, align: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.03) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
        )
    }

    private func headerCell(_ text: String, width: CGFloat, align: Alignment) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(align == .leading ? .leading : .center)
            .frame(width: width, alignment: align)
    }

    private func valueCell(_ text: String, width: CGFloat, align: Alignment) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(align == .leading ? .leading : .center)
            .frame(width: width, alignment: align)
    }

    private func tableDivider() -> some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(width: 1, height: 16)
    }

    private var benchmarkCooldownLabel: String? {
        guard let cooldownEndsAt else { return nil }
        let remaining = max(0, cooldownEndsAt.timeIntervalSince(now))
        guard remaining > 0 else { return nil }
        let seconds = Int(remaining.rounded(.up))
        let minutesPart = seconds / 60
        let secondsPart = seconds % 60
        if minutesPart > 0 {
            return "\(minutesPart)m \(secondsPart)s"
        }
        return "\(secondsPart)s"
    }

    private var canTriggerBenchmark: Bool {
        benchmark?.running != true && benchmarkCooldownLabel == nil
    }

    private func suiteLabel(_ suite: String?) -> String {
        guard let suite, !suite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Unknown"
        }
        let normalized = suite.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "quick" { return "Default" }
        return normalized
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }

    private func formattedGeneratedAt(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Unknown" }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            return date.formatted(date: .abbreviated, time: .standard)
        }
        return value
    }

    private func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f", value)
    }

    private func tps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    private func mb(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f", value)
    }

    private func exportCSV() {
        guard let latest = benchmark?.latest, !latest.rows.isEmpty else {
            exportNotice = ExportNotice(message: "No benchmark data to export yet.", isError: true)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Benchmark CSV"
        panel.prompt = "Export"
        panel.nameFieldStringValue = defaultCSVFileName(latest.generatedAt)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try makeCSV(from: latest).write(to: url, atomically: true, encoding: .utf8)
                exportNotice = ExportNotice(message: "Exported CSV to \(url.lastPathComponent).", isError: false)
            } catch {
                exportNotice = ExportNotice(message: "CSV export failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func makeCSV(from latest: BenchmarkLatestReport) -> String {
        var lines: [String] = []
        lines.append("suite,generated_at,profile,runtime,ttft_ms,decode_tps,e2e_tps,rss_mb")
        for row in latest.rows {
            lines.append([
                csvField(latest.suite ?? ""),
                csvField(latest.generatedAt ?? ""),
                csvField(row.profile ?? ""),
                csvField(row.runtime ?? ""),
                csvField(ms(row.ttftMS)),
                csvField(tps(row.decodeTokensPerSec)),
                csvField(tps(row.e2eTokensPerSec)),
                csvField(mb(row.rssMB))
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func defaultCSVFileName(_ generatedAt: String?) -> String {
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

    private var activeRunLabel: String {
        if activeBenchmarkProfiles.isEmpty {
            return "Benchmark is running for all profiles."
        }
        if activeBenchmarkProfiles.count == 1, let only = activeBenchmarkProfiles.first {
            return "Benchmark is running for profile: \(only)."
        }
        return "Benchmark is running for \(activeBenchmarkProfiles.count) selected profiles."
    }

    private var benchmarkActionButton: some View {
        Button("Run Benchmark", action: runBenchmark)
            .controlSize(.small)
            .disabled(!canTriggerBenchmark)
    }

    private var exportButton: some View {
        Button("Export CSV") {
            exportCSV()
        }
        .controlSize(.small)
        .disabled((benchmark?.latest?.rows.isEmpty ?? true) || benchmark?.running == true)
    }

    private func metricsStrip(rows: [BenchmarkLatestRow]) -> some View {
        let decodeValues = rows.compactMap(\.decodeTokensPerSec)
        let ttftValues = rows.compactMap(\.ttftMS)
        let avgDecode = decodeValues.isEmpty ? "—" : String(format: "%.1f tok/s", decodeValues.reduce(0, +) / Double(decodeValues.count))
        let bestTTFT = ttftValues.min().map { String(format: "%.0f ms", $0) } ?? "—"

        return HStack(spacing: 8) {
            metricPill(title: "Profiles", value: "\(rows.count)")
            metricPill(title: "Avg Decode", value: avgDecode)
            metricPill(title: "Best TTFT", value: bestTTFT)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
    }

    private func comparisonStrip(rows: [BenchmarkLatestRow]) -> some View {
        let bestDecode = rows.max(by: { ($0.decodeTokensPerSec ?? 0) < ($1.decodeTokensPerSec ?? 0) })
        let bestTTFT = rows.min(by: { ($0.ttftMS ?? .greatestFiniteMagnitude) < ($1.ttftMS ?? .greatestFiniteMagnitude) })
        let decodeText = benchmarkName(bestDecode) + " (\(tps(bestDecode?.decodeTokensPerSec)))"
        let ttftText = benchmarkName(bestTTFT) + " (\(ms(bestTTFT?.ttftMS)) ms)"

        return HStack(spacing: 8) {
            compactMetric("Fastest Decode", decodeText)
            compactMetric("Best TTFT", ttftText)
        }
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.bold())
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benchmarkName(_ row: BenchmarkLatestRow?) -> String {
        (row?.profile ?? row?.runtime ?? "unknown")
    }

    private func compactProfileName(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 18 else { return value }
        return String(value.prefix(17)) + "…"
    }

    private func sortedRowsForDisplay(_ rows: [BenchmarkLatestRow]) -> [BenchmarkLatestRow] {
        guard rows.count > 1 else { return rows }
        return rows.sorted { lhs, rhs in
            (lhs.decodeTokensPerSec ?? -1) > (rhs.decodeTokensPerSec ?? -1)
        }
    }

    private func columnWidths(totalWidth: CGFloat) -> ColumnWidths {
        let dividerWidthTotal: CGFloat = 4
        let usable = max(200, totalWidth - dividerWidthTotal)
        let profile = floor(usable * 0.30)
        let ttft = floor(usable * 0.15)
        let decode = floor(usable * 0.19)
        let e2e = floor(usable * 0.16)
        let rss = max(28, usable - profile - ttft - decode - e2e)
        return ColumnWidths(profile: profile, ttft: ttft, decode: decode, e2e: e2e, rss: rss)
    }
}

private struct ExportNotice: Equatable {
    let message: String
    let isError: Bool
}

private struct ColumnWidths {
    let profile: CGFloat
    let ttft: CGFloat
    let decode: CGFloat
    let e2e: CGFloat
    let rss: CGFloat
}
