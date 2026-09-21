import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
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
      reports.append(
        try runProfile(
          name: name,
          profile: profile,
          prompts: prompts,
          allowConcurrent: allowConcurrent,
          keepRunning: keepRunning
        )
      )
    }
    try writeLatest(suite: suite, names: names, reports: reports)
  }
}
