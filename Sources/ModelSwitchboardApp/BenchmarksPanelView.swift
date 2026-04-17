import SwiftUI
import ModelSwitchboardCore

struct BenchmarksPanelView: View {
    let benchmark: BenchmarkStatus?
    let runBenchmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Latest")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                statusChip
                Spacer()
                Button("Run Benchmark", action: runBenchmark)
                    .controlSize(.small)
                    .disabled(benchmark?.running == true)
            }

            if let latest = benchmark?.latest {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suite: \(suiteLabel(latest.suite))")
                        .font(.footnote.weight(.semibold))
                    Text("Generated: \(formattedGeneratedAt(latest.generatedAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No benchmark recorded yet. Run a benchmark to populate this panel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rows = benchmark?.latest?.rows, !rows.isEmpty {
                tableView(rows: rows)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                benchmarkHeader
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    benchmarkRow(row)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var benchmarkHeader: some View {
        HStack(spacing: 10) {
            cell("Profile", width: 120, align: .leading, isHeader: true)
            cell("TTFT", width: 62, align: .trailing, isHeader: true)
            cell("Decode", width: 70, align: .trailing, isHeader: true)
            cell("E2E", width: 62, align: .trailing, isHeader: true)
            cell("RSS", width: 70, align: .trailing, isHeader: true)
        }
        .padding(.top, 8)
        .padding(.horizontal, 8)
    }

    private func benchmarkRow(_ row: BenchmarkLatestRow) -> some View {
        HStack(spacing: 10) {
            cell(row.profile ?? row.runtime ?? "unknown", width: 120, align: .leading)
            cell(ms(row.ttftMS), width: 62, align: .trailing)
            cell(tps(row.decodeTokensPerSec), width: 70, align: .trailing)
            cell(tps(row.e2eTokensPerSec), width: 62, align: .trailing)
            cell(mb(row.rssMB), width: 70, align: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func cell(_ text: String, width: CGFloat, align: Alignment, isHeader: Bool = false) -> some View {
        Text(text)
            .font(isHeader ? .caption2.bold() : .caption2.monospacedDigit())
            .foregroundStyle(isHeader ? Color.secondary : Color.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: align)
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
}
