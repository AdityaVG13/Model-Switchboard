import Foundation
import ModelSwitchboardCore

public final class BenchmarkService: @unchecked Sendable {
  unowned let service: ControllerService
  let fileManager = FileManager.default

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

  var pidFile: URL {
    service.configuration.runDirectory.appendingPathComponent("benchmark.pid")
  }

  func readPID() -> Int? {
    (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap {
      Int($0.trimmed)
    }
  }

  func currentLogPath() -> URL {
    return service.configuration.runDirectory.appendingPathComponent("logs/benchmark.log")
  }
}
