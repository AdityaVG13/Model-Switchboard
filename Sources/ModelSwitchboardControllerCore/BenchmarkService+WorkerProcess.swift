import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
  func prepareBenchmarkLog() throws -> URL {
    let logDirectory = service.configuration.runDirectory.appendingPathComponent(
      "logs", isDirectory: true)
    try fileManager.createDirectory(
      at: logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let logURL = logDirectory.appendingPathComponent("benchmark.log")
    try? fileManager.removeItem(at: logURL)
    fileManager.createFile(
      atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
    return logURL
  }

  func makeBenchmarkWorkerProcess(
    profiles: [String]?,
    suite: String,
    allowConcurrent: Bool,
    keepRunning: Bool,
    logHandle: FileHandle
  ) -> Process {
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
    process.standardOutput = logHandle
    process.standardError = logHandle
    process.terminationHandler = { [pidFile] _ in try? FileManager.default.removeItem(at: pidFile) }
    return process
  }
}
