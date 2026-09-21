import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
    var latestJSON: URL {
        service.configuration.benchmarkResultsDirectory.appendingPathComponent("latest.json")
    }

    var latestMarkdown: URL {
        service.configuration.benchmarkResultsDirectory.appendingPathComponent("latest.md")
    }

    func latestReport() -> BenchmarkLatestReport? {
        guard let payload = latestJSONObject() else { return nil }
        let reports = payload["benchmarks"] as? [[String: Any]] ?? []
        return BenchmarkLatestReport(
            generatedAt: payload["generated_at"] as? String,
            suite: payload["suite"] as? String,
            profiles: payload["profiles"] as? [String] ?? [],
            rows: reports.map(latestRow),
            jsonPath: latestJSON.path,
            markdownPath: latestMarkdown.path
        )
    }

    func latestJSONObject() -> [String: Any]? {
        guard let data = try? Data(contentsOf: latestJSON) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
