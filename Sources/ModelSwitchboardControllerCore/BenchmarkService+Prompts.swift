import Foundation

extension BenchmarkService {
  struct PromptCase {
    let name: String
    let category: String
    let prompt: String
    let maxTokens: Int
    let estimatedTokens: Int
  }

  func promptCases(suite: String) -> [PromptCase] {
    let quick = [
      PromptCase(
        name: "instruction", category: "general",
        prompt: "Explain why local inference can improve privacy in three concise points.",
        maxTokens: 128, estimatedTokens: 16),
      PromptCase(
        name: "coding", category: "coding",
        prompt: "Write a Swift function that removes duplicates while preserving order.",
        maxTokens: 192, estimatedTokens: 14),
    ]
    guard suite == "context" else { return quick }
    return [1_024, 4_096, 8_192].map { count in
      let repeated = String(repeating: "local model benchmark context ", count: max(1, count / 5))
      return PromptCase(
        name: "prefill-\(count / 1024)k", category: "prefill",
        prompt: repeated + "\nSummarize in one sentence.", maxTokens: 64, estimatedTokens: count)
    }
  }

  func markdown(payload: [String: Any], reports: [[String: Any]]) -> String {
    var lines = [
      "# Model Switchboard Benchmark", "", "Generated: \(payload["generated_at"] ?? "")", "",
      "| Profile | Runtime | TTFT ms | Decode tok/s |", "|---|---|---:|---:|",
    ]
    for report in reports {
      let averages = report["averages"] as? [String: Any] ?? [:]
      lines.append(
        "| \(report["profile"] ?? "") | \(report["runtime"] ?? "") | \(averages["ttft_ms"] ?? "-") | \(averages["decode_tokens_per_sec"] ?? "-") |"
      )
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
