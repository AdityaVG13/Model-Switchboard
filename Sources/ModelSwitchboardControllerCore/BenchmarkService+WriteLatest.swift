import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
    func writeLatest(suite: String, names: [String], reports: [[String: Any]]) throws {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "generated_at": generatedAt,
            "suite": suite,
            "profiles": names,
            "benchmarks": reports,
        ]
        try fileManager.createDirectory(
            at: service.configuration.benchmarkResultsDirectory, withIntermediateDirectories: true)
        var data = try JSONSupport.data(payload)
        data.append(0x0A)
        try data.write(to: latestJSON, options: .atomic)
        try markdown(payload: payload, reports: reports).write(
            to: latestMarkdown, atomically: true, encoding: .utf8)
    }
}
