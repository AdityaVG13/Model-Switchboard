import Foundation
import ModelSwitchboardCore

enum BenchmarkMetricFormatting {
    static func milliseconds(_ value: Double?) -> String {
        formatted(value, digits: 0)
    }

    static func tokensPerSecond(_ value: Double?) -> String {
        formatted(value, digits: 1)
    }

    static func megabytes(_ value: Double?) -> String {
        formatted(value, digits: 0)
    }

    static func formatted(_ value: Double?, digits: Int) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }

    static func suiteLabel(_ suite: String?) -> String {
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

    static func compactProfileName(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 18 else { return value }
        return String(value.prefix(17)) + "…"
    }

    static func benchmarkName(_ row: BenchmarkLatestRow?) -> String {
        (row?.profile ?? row?.runtime ?? "unknown")
    }

    static func sortedRowsForDisplay(_ rows: [BenchmarkLatestRow]) -> [BenchmarkLatestRow] {
        guard rows.count > 1 else { return rows }
        return rows.sorted { lhs, rhs in
            (lhs.decodeTokensPerSec ?? -1) > (rhs.decodeTokensPerSec ?? -1)
        }
    }
}
