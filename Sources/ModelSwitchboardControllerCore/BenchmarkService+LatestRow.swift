import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
    func latestRow(_ report: [String: Any]) -> BenchmarkLatestRow {
        let averages = report["averages"] as? [String: Any] ?? [:]
        let results = report["results"] as? [[String: Any]] ?? []
        let prefill = results.compactMap(prefillCase)
        return BenchmarkLatestRow(
            profile: report["profile"] as? String,
            runtime: report["runtime"] as? String,
            ttftMS: (averages["ttft_ms"] as? NSNumber)?.doubleValue,
            decodeTokensPerSec: (averages["decode_tokens_per_sec"] as? NSNumber)?.doubleValue,
            e2eTokensPerSec: (averages["e2e_tokens_per_sec"] as? NSNumber)?.doubleValue,
            rssMB: (report["rss_mb"] as? NSNumber)?.doubleValue,
            prefillCases: prefill.isEmpty ? nil : prefill
        )
    }

    func prefillCase(_ item: [String: Any]) -> BenchmarkPrefillCase? {
        guard item["category"] as? String == "prefill" else { return nil }
        return BenchmarkPrefillCase(
            label: (item["benchmark"] as? String ?? "").replacingOccurrences(of: "prefill-", with: ""),
            promptEstTokens: (item["prompt_est_tokens"] as? NSNumber)?.intValue,
            ttftMS: (item["ttft_ms"] as? NSNumber)?.doubleValue,
            decodeTokensPerSec: (item["decode_tokens_per_sec"] as? NSNumber)?.doubleValue
        )
    }
}
