import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
    func runProfile(
        name: String,
        profile: ControllerProfile,
        prompts: [PromptCase],
        allowConcurrent: Bool,
        keepRunning: Bool
    ) throws -> [String: Any] {
        let before = service.status(for: profile)
        if !before.ready {
            if allowConcurrent { try service.start(name) } else { try service.switchProfile(name) }
            waitUntilReady(profile)
        }
        let results = prompts.map { run(prompt: $0, profile: profile) }
        let successful = results.filter { $0["error"] == nil }
        let current = service.status(for: profile)
        if !keepRunning, !before.running { try? service.stop(name) }
        return [
            "profile": name,
            "runtime": profile.runtime,
            "rss_mb": current.rssMB as Any,
            "averages": [
                "ttft_ms": average(successful.compactMap { $0["ttft_ms"] as? Double }) as Any,
                "decode_tokens_per_sec": average(successful.compactMap { $0["decode_tokens_per_sec"] as? Double }) as Any,
                "e2e_tokens_per_sec": average(successful.compactMap { $0["e2e_tokens_per_sec"] as? Double }) as Any,
            ],
            "results": results,
        ]
    }
}
