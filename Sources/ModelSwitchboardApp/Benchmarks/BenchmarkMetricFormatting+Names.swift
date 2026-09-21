import Foundation
import ModelSwitchboardCore

extension BenchmarkMetricFormatting {
    static func compactProfileName(_ raw: String) -> String {
        let value = raw.trimmed
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
