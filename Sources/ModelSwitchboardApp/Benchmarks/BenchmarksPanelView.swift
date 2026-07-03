import SwiftUI
import ModelSwitchboardCore

struct BenchmarksPanelView: View {
    let benchmark: BenchmarkStatus?
    let activeBenchmarkProfiles: [String]
    let cooldownEndsAt: Date?
    let runBenchmark: () -> Void
    @State private var exportNotice: BenchmarkCSVExport.Notice?
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
                    Text("Suite: \(BenchmarkMetricFormatting.suiteLabel(latest.suite))")
                        .font(.footnote.weight(.semibold))
                    Text("Generated: \(BenchmarkTimestampFormatting.formattedGeneratedAt(latest.generatedAt))")
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
        let displayRows = BenchmarkMetricFormatting.sortedRowsForDisplay(rows)
        let rowHeight: CGFloat = 32
        let maxTableHeight: CGFloat = 320
        let interRowSpacing: CGFloat = 4
        let contentPadding: CGFloat = 10
        let scrollbarGutter: CGFloat = displayRows.count > 7 ? 14 : 0
        let rowCount = CGFloat(displayRows.count)
        let spacingCount = CGFloat(max(0, displayRows.count - 1))
        let contentHeight: CGFloat = rowCount * rowHeight + spacingCount * interRowSpacing + contentPadding
        let desiredHeight: CGFloat = min(maxTableHeight, max(rowHeight + contentPadding, contentHeight))
        let comparisonHeight: CGFloat = displayRows.count > 1 ? 44 : 0

        return GeometryReader { proxy in
            let widths = BenchmarkColumnWidths.forTotalWidth(max(220, proxy.size.width - 16))
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
                    .padding(.trailing, scrollbarGutter)
                }
                .frame(height: desiredHeight)
                .scrollIndicators(.visible)
            }
            .padding(8)
            .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(height: desiredHeight + 40 + comparisonHeight)
    }

    private func benchmarkHeader(_ widths: BenchmarkColumnWidths) -> some View {
        HStack(spacing: 0) {
            BenchmarkTableComponents.headerCell("Profile", width: widths.profile, align: .center)
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.headerCell("TTFT", width: widths.ttft, align: .center)
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.headerCell("Decode", width: widths.decode, align: .center)
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.headerCell("E2E", width: widths.e2e, align: .center)
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.headerCell("RSS", width: widths.rss, align: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func benchmarkRow(_ row: BenchmarkLatestRow, index: Int, widths: BenchmarkColumnWidths) -> some View {
        HStack(spacing: 0) {
            BenchmarkTableComponents.valueCell(
                BenchmarkMetricFormatting.compactProfileName(row.profile ?? row.runtime ?? "unknown"),
                width: widths.profile,
                align: .center
            )
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.valueCell(BenchmarkMetricFormatting.milliseconds(row.ttftMS), width: widths.ttft, align: .center)
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.valueCell(BenchmarkMetricFormatting.tokensPerSecond(row.decodeTokensPerSec), width: widths.decode, align: .center)
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.valueCell(BenchmarkMetricFormatting.tokensPerSecond(row.e2eTokensPerSec), width: widths.e2e, align: .center)
            BenchmarkTableComponents.tableDivider()
            BenchmarkTableComponents.valueCell(BenchmarkMetricFormatting.megabytes(row.rssMB), width: widths.rss, align: .center)
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

    private var benchmarkCooldownLabel: String? {
        guard let cooldownEndsAt else { return nil }
        return DurationFormatting.compactCountdown(endsAt: cooldownEndsAt, relativeTo: now)
    }

    private var canTriggerBenchmark: Bool {
        benchmark?.running != true && benchmarkCooldownLabel == nil
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
            guard let latest = benchmark?.latest else { return }
            BenchmarkCSVExport.presentSavePanel(for: latest) { notice in
                exportNotice = notice
            }
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
            BenchmarkTableComponents.metricPill(title: "Profiles", value: "\(rows.count)")
            BenchmarkTableComponents.metricPill(title: "Avg Decode", value: avgDecode)
            BenchmarkTableComponents.metricPill(title: "Best TTFT", value: bestTTFT)
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonStrip(rows: [BenchmarkLatestRow]) -> some View {
        let bestDecode = rows.max(by: { ($0.decodeTokensPerSec ?? 0) < ($1.decodeTokensPerSec ?? 0) })
        let bestTTFT = rows.min(by: { ($0.ttftMS ?? .greatestFiniteMagnitude) < ($1.ttftMS ?? .greatestFiniteMagnitude) })
        let decodeText = BenchmarkMetricFormatting.benchmarkName(bestDecode) + " (\(BenchmarkMetricFormatting.tokensPerSecond(bestDecode?.decodeTokensPerSec)))"
        let ttftText = BenchmarkMetricFormatting.benchmarkName(bestTTFT) + " (\(BenchmarkMetricFormatting.milliseconds(bestTTFT?.ttftMS)) ms)"

        return HStack(spacing: 8) {
            BenchmarkTableComponents.compactMetric("Fastest Decode", decodeText)
            BenchmarkTableComponents.compactMetric("Best TTFT", ttftText)
        }
    }

    static func formattedGeneratedAt(_ value: String?) -> String {
        BenchmarkTimestampFormatting.formattedGeneratedAt(value)
    }

    static func parsedGeneratedAt(_ value: String?) -> Date? {
        BenchmarkTimestampFormatting.parsedGeneratedAt(value)
    }
}
