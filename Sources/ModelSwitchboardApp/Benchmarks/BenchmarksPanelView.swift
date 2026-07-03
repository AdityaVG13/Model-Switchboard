import SwiftUI
import ModelSwitchboardCore

struct BenchmarksPanelView: View {
    let benchmark: BenchmarkStatus?
    let activeBenchmarkProfiles: [String]
    let cooldownEndsAt: Date?
    let theme: DashboardTheme
    let accent: Color
    let runBenchmark: () -> Void
    @State private var exportNotice: BenchmarkCSVExport.Notice?
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if benchmark?.running == true {
                        noticeText(activeRunLabel, color: DashboardTheme.pendingOrange)
                        noticeText("The results below show the latest completed run until this benchmark finishes.", color: theme.sub)
                    } else if let benchmarkCooldownLabel {
                        noticeText("Benchmark cooldown: \(benchmarkCooldownLabel) remaining.", color: theme.sub)
                    }

                    if let exportNotice {
                        noticeText(exportNotice.message, color: exportNotice.isError ? DashboardTheme.stopRed : DashboardTheme.runningGreen)
                    }

                    if let latest = benchmark?.latest, !latest.rows.isEmpty {
                        let best = BenchmarkMetricFormatting.sortedRowsForDisplay(latest.rows).first
                        summaryCard(latest)
                        if let cases = best?.prefillCases, !cases.isEmpty {
                            prefillSection(cases)
                            theme.line.frame(height: 1)
                                .padding(.bottom, 4)
                        }
                        rankedRows(latest)
                    } else {
                        noticeText("No benchmark recorded yet. Run a benchmark to populate this panel.", color: theme.sub)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)

            theme.line.frame(height: 1)
            panelFooter
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
    }

    // MARK: - Summary card

    private func summaryCard(_ latest: BenchmarkLatestReport) -> some View {
        let best = BenchmarkMetricFormatting.sortedRowsForDisplay(latest.rows).first

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(latestRunLabel(latest.generatedAt))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(theme.faint)
                Text(BenchmarkMetricFormatting.benchmarkName(best))
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("suite \(BenchmarkMetricFormatting.suiteLabel(latest.suite).lowercased()) \u{00b7} \(best?.runtime ?? "\u{2014}")")
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

    private func metricColumn(_ value: String, unit: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(emphasized ? accent : .primary)
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(theme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Prefill scaling

    private func prefillSection(_ cases: [BenchmarkPrefillCase]) -> some View {
        let maxTTFT = max(cases.compactMap(\.ttftMS).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 0) {
            Text("PREFILL SCALING \u{00b7} TTFT BY CONTEXT")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.faint)
                .padding(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            ForEach(Array(cases.enumerated()), id: \.offset) { _, benchCase in
                prefillRow(benchCase, maxTTFT: maxTTFT)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 10))
    }

    private func prefillRow(_ benchCase: BenchmarkPrefillCase, maxTTFT: Double) -> some View {
        let fraction = max(0, min(1, (benchCase.ttftMS ?? 0) / maxTTFT))

        return HStack(spacing: 10) {
            Text(benchCase.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.sub)
                .frame(width: 30, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.cellBg)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent)
                        .frame(width: proxy.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 6)
            .frame(maxWidth: .infinity)

            Text("\(BenchmarkMetricFormatting.milliseconds(benchCase.ttftMS)) ms")
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
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

    // MARK: - Ranked rows

    private func rankedRows(_ latest: BenchmarkLatestReport) -> some View {
        let rows = BenchmarkMetricFormatting.sortedRowsForDisplay(latest.rows)
        let maxDecode = max(rows.compactMap(\.decodeTokensPerSec).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 0) {
            Text("ALL MODELS \u{00b7} BEST DECODE")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.faint)
                .padding(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                rankedRow(row, isTop: index == 0, maxDecode: maxDecode)
            }
        }
        .padding(.horizontal, 10)
    }

    private func rankedRow(_ row: BenchmarkLatestRow, isTop: Bool, maxDecode: Double) -> some View {
        let fraction = max(0, min(1, (row.decodeTokensPerSec ?? 0) / maxDecode))

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(BenchmarkMetricFormatting.benchmarkName(row))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let runtime = row.runtime {
                    Text(runtime)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.cellBg)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isTop ? accent : theme.sparkStroke)
                        .frame(width: proxy.size.width * CGFloat(fraction))
                }
            }
            .frame(width: 70, height: 5)

            Text("\(BenchmarkMetricFormatting.tokensPerSecond(row.decodeTokensPerSec)) t/s")
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .frame(width: 62, alignment: .trailing)
        }
        .padding(EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6))
    }

    // MARK: - Footer

    private var panelFooter: some View {
        HStack {
            Button {
                runBenchmark()
            } label: {
                Text(runButtonTitle)
                    .font(.system(size: 11.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canTriggerBenchmark ? theme.btnFg : theme.faint)
            .disabled(!canTriggerBenchmark)

            Spacer()

            Button {
                guard let latest = benchmark?.latest else { return }
                BenchmarkCSVExport.presentSavePanel(for: latest) { notice in
                    exportNotice = notice
                }
            } label: {
                Text("Export CSV")
                    .font(.system(size: 11.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canExport ? theme.btnFg : theme.faint)
            .disabled(!canExport)
        }
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
    }

    // MARK: - State helpers

    private var canTriggerBenchmark: Bool {
        benchmark?.running != true && benchmarkCooldownLabel == nil
    }

    private var canExport: Bool {
        !(benchmark?.latest?.rows.isEmpty ?? true) && benchmark?.running != true
    }

    private var runButtonTitle: String {
        if benchmark?.running == true { return "Benchmark Running\u{2026}" }
        if let suite = benchmark?.latest?.suite, !suite.isEmpty {
            return "Run Suite: \(BenchmarkMetricFormatting.suiteLabel(suite).lowercased())"
        }
        return "Run Benchmark"
    }

    private var benchmarkCooldownLabel: String? {
        guard let cooldownEndsAt else { return nil }
        return DurationFormatting.compactCountdown(endsAt: cooldownEndsAt, relativeTo: now)
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

    private func noticeText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 6, leading: 14, bottom: 0, trailing: 14))
    }

    private func gigabytes(_ megabytes: Double?) -> String {
        guard let megabytes else { return "\u{2014}" }
        return String(format: "%.1f", megabytes / 1024)
    }

    private func latestRunLabel(_ generatedAt: String?) -> String {
        guard let date = Self.parsedGeneratedAt(generatedAt) else { return "LATEST RUN" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "LATEST RUN \u{00b7} \(formatter.string(from: date).uppercased())"
    }

    // MARK: - Timestamp passthroughs (kept: covered by tests)

    static func formattedGeneratedAt(_ value: String?) -> String {
        BenchmarkTimestampFormatting.formattedGeneratedAt(value)
    }

    static func parsedGeneratedAt(_ value: String?) -> Date? {
        BenchmarkTimestampFormatting.parsedGeneratedAt(value)
    }
}
