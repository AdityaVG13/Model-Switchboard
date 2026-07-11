import Foundation
import ModelSwitchboardCore

public final class BenchmarkService: @unchecked Sendable {
  private unowned let service: ControllerService
  private let fileManager = FileManager.default

  init(service: ControllerService) {
    self.service = service
  }

  public func status() -> BenchmarkStatus {
    var pid = readPID()
    if let current = pid, !ProcessRunner.processIsAlive(current) {
      try? fileManager.removeItem(at: pidFile)
      pid = nil
    }
    return BenchmarkStatus(
      running: pid != nil,
      pid: pid,
      logPath: currentLogPath().path,
      latest: latestReport()
    )
  }

  public func start(
    profiles: [String]?,
    suite: String,
    allowConcurrent: Bool,
    keepRunning: Bool
  ) throws -> BenchmarkStatus {
    if status().running { throw ControllerError.operationFailed("benchmark already running") }
    try fileManager.createDirectory(
      at: service.configuration.runDirectory, withIntermediateDirectories: true)
    let logDirectory = service.configuration.runDirectory.appendingPathComponent(
      "logs", isDirectory: true)
    try fileManager.createDirectory(
      at: logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let logURL = logDirectory.appendingPathComponent("benchmark.log")
    try? fileManager.removeItem(at: logURL)
    fileManager.createFile(
      atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let handle = try FileHandle(forWritingTo: logURL)

    let process = Process()
    process.executableURL = service.controllerExecutableURL
    var arguments = [
      "benchmark-worker", "--root", service.configuration.root.path, "--suite", suite,
    ]
    if let profiles, !profiles.isEmpty {
      arguments += ["--profiles", profiles.joined(separator: ",")]
    }
    if allowConcurrent { arguments.append("--allow-concurrent") }
    if keepRunning { arguments.append("--keep-running") }
    process.arguments = arguments
    process.currentDirectoryURL = service.configuration.root
    process.standardOutput = handle
    process.standardError = handle
    process.terminationHandler = { [pidFile] _ in try? FileManager.default.removeItem(at: pidFile) }
    try process.run()
    try handle.close()
    try "\(process.processIdentifier)\n".write(to: pidFile, atomically: true, encoding: .utf8)
    return status()
  }

  public func runWorker(
    selectedNames: [String]?,
    suite: String,
    allowConcurrent: Bool,
    keepRunning: Bool
  ) throws {
    let loaded = try service.profiles.load()
    let names = selectedNames?.filter { loaded[$0] != nil } ?? loaded.keys.sorted()
    let prompts = promptCases(suite: suite)
    var reports: [[String: Any]] = []
    for name in names {
      guard let profile = loaded[name] else { continue }
      let before = service.status(for: profile)
      if !before.ready {
        if allowConcurrent { try service.start(name) } else { try service.switchProfile(name) }
        waitUntilReady(profile)
      }
      var results: [[String: Any]] = []
      for prompt in prompts {
        results.append(run(prompt: prompt, profile: profile))
      }
      let successful = results.filter { $0["error"] == nil }
      let ttft = average(successful.compactMap { $0["ttft_ms"] as? Double })
      let decode = average(successful.compactMap { $0["decode_tokens_per_sec"] as? Double })
      let e2e = average(successful.compactMap { $0["e2e_tokens_per_sec"] as? Double })
      let current = service.status(for: profile)
      reports.append([
        "profile": name,
        "runtime": profile.runtime,
        "rss_mb": current.rssMB as Any,
        "averages": [
          "ttft_ms": ttft as Any, "decode_tokens_per_sec": decode as Any,
          "e2e_tokens_per_sec": e2e as Any,
        ],
        "results": results,
      ])
      if !keepRunning, !before.running { try? service.stop(name) }
    }
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

  private struct PromptCase {
    let name: String
    let category: String
    let prompt: String
    let maxTokens: Int
    let estimatedTokens: Int
  }

  private func promptCases(suite: String) -> [PromptCase] {
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

  private func run(prompt: PromptCase, profile: ControllerProfile) -> [String: Any] {
    guard let endpoint = URL(string: "\(profile.baseURL)/chat/completions") else {
      return ["benchmark": prompt.name, "category": prompt.category, "error": "invalid endpoint"]
    }
    let request: [String: Any] = [
      "model": profile.requestModel,
      "messages": [["role": "user", "content": prompt.prompt]],
      "max_tokens": prompt.maxTokens,
      "stream": false,
      "temperature": 0,
    ]
    guard let requestData = try? JSONSupport.data(request) else {
      return ["benchmark": prompt.name, "category": prompt.category, "error": "encoding failed"]
    }
    let start = Date()
    let result: ProcessResult
    do {
      result = try ProcessRunner.run(
        "/usr/bin/curl",
        [
          "--fail", "--silent", "--show-error", "--max-time", "120",
          "--header", "Content-Type: application/json", "--data-binary",
          String(decoding: requestData, as: UTF8.self), endpoint.absoluteString,
        ])
    } catch {
      return [
        "benchmark": prompt.name, "category": prompt.category,
        "prompt_est_tokens": prompt.estimatedTokens, "error": String(describing: error),
      ]
    }
    let elapsed = Date().timeIntervalSince(start) * 1_000
    let response =
      result.stdout.data(using: .utf8).flatMap {
        try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
      } ?? [:]
    let usage = response["usage"] as? [String: Any] ?? [:]
    let completionTokens = (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0
    let promptTokens = (usage["prompt_tokens"] as? NSNumber)?.intValue ?? prompt.estimatedTokens
    let seconds = max(elapsed / 1_000, 0.001)
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
      "ttft_ms": elapsed,
      "total_ms": elapsed,
      "decode_tokens_per_sec": Double(completionTokens) / seconds,
      "e2e_tokens_per_sec": Double(promptTokens + completionTokens) / seconds,
      "output_preview": String(content.prefix(240)),
    ]
  }

  private func waitUntilReady(_ profile: ControllerProfile) {
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
      if service.status(for: profile).ready { return }
      Thread.sleep(forTimeInterval: 1)
    }
  }

  private func average(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
  }

  private func latestReport() -> BenchmarkLatestReport? {
    guard let data = try? Data(contentsOf: latestJSON),
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let reports = payload["benchmarks"] as? [[String: Any]] ?? []
    let rows = reports.map { report -> BenchmarkLatestRow in
      let averages = report["averages"] as? [String: Any] ?? [:]
      let results = report["results"] as? [[String: Any]] ?? []
      let prefill = results.filter { $0["category"] as? String == "prefill" }.map { item in
        BenchmarkPrefillCase(
          label: (item["benchmark"] as? String ?? "").replacingOccurrences(
            of: "prefill-", with: ""),
          promptEstTokens: (item["prompt_est_tokens"] as? NSNumber)?.intValue,
          ttftMS: (item["ttft_ms"] as? NSNumber)?.doubleValue,
          decodeTokensPerSec: (item["decode_tokens_per_sec"] as? NSNumber)?.doubleValue
        )
      }
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
    return BenchmarkLatestReport(
      generatedAt: payload["generated_at"] as? String,
      suite: payload["suite"] as? String,
      profiles: payload["profiles"] as? [String] ?? [],
      rows: rows,
      jsonPath: latestJSON.path,
      markdownPath: latestMarkdown.path
    )
  }

  private func markdown(payload: [String: Any], reports: [[String: Any]]) -> String {
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

  private var pidFile: URL {
    service.configuration.runDirectory.appendingPathComponent("benchmark.pid")
  }
  private var latestJSON: URL {
    service.configuration.benchmarkResultsDirectory.appendingPathComponent("latest.json")
  }
  private var latestMarkdown: URL {
    service.configuration.benchmarkResultsDirectory.appendingPathComponent("latest.md")
  }

  private func readPID() -> Int? {
    (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap {
      Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private func currentLogPath() -> URL {
    return service.configuration.runDirectory.appendingPathComponent("logs/benchmark.log")
  }
}
