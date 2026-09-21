import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
    func decodeBenchmark(prompt: PromptCase, result: ProcessResult, elapsedMS: Double) -> [String: Any] {
        let response =
            result.stdout.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
        let usage = response["usage"] as? [String: Any] ?? [:]
        let completionTokens = (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0
        let promptTokens = (usage["prompt_tokens"] as? NSNumber)?.intValue ?? prompt.estimatedTokens
        let seconds = max(elapsedMS / 1_000, 0.001)
        let content =
            (((response["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"]
                as? String) ?? ""
        return [
            "benchmark": prompt.name,
            "category": prompt.category,
            "prompt": prompt.prompt,
            "prompt_est_tokens": prompt.estimatedTokens,
            "prompt_tokens": promptTokens,
            "completion_tokens": completionTokens,
            "ttft_ms": elapsedMS,
            "total_ms": elapsedMS,
            "decode_tokens_per_sec": Double(completionTokens) / seconds,
            "e2e_tokens_per_sec": Double(promptTokens + completionTokens) / seconds,
            "output_preview": String(content.prefix(240)),
        ]
    }

    func waitUntilReady(_ profile: ControllerProfile) {
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if service.status(for: profile).ready { return }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
