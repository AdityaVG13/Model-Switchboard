import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
  public func start(
    profiles: [String]?,
    suite: String,
    allowConcurrent: Bool,
    keepRunning: Bool
  ) throws -> BenchmarkStatus {
    // SAFETY (TOCTOU): status() -> running-check -> pid-write is not atomic.
    // Two concurrent `start` calls could both see no pid file and both spawn
    // a benchmark. Accepted: the controller serves HTTP on one serial
    // DispatchQueue and `model-switchboardctl benchmark` is a single operator
    // invocation. If the controller ever handles requests concurrently,
    // serialize start() through ControllerService's mutationLock first.
    if status().running { throw ControllerError.operationFailed("benchmark already running") }
    try fileManager.createDirectory(
      at: service.configuration.runDirectory, withIntermediateDirectories: true)
    let logURL = try prepareBenchmarkLog()
    let handle = try FileHandle(forWritingTo: logURL)
    let process = makeBenchmarkWorkerProcess(
      profiles: profiles,
      suite: suite,
      allowConcurrent: allowConcurrent,
      keepRunning: keepRunning,
      logHandle: handle
    )
    try process.run()
    try handle.close()
    try "\(process.processIdentifier)\n".write(to: pidFile, atomically: true, encoding: .utf8)
    return status()
  }
}
