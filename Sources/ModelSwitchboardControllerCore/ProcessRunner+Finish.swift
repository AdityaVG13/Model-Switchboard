import Foundation
import ModelSwitchboardCore

extension ProcessRunner {
  static func finish(_ process: Process, stdout: Pipe, stderr: Pipe) -> ProcessResult {
    // Drain both pipes BEFORE waiting for exit: readDataToEndOfFile returns
    // when the child closes its write end, so this cannot deadlock. Waiting
    // first would hang once output exceeds the 64KB pipe buffer (the child
    // blocks writing while we block on exit).
    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(
      status: process.terminationStatus,
      stdout: String(decoding: stdoutData, as: UTF8.self),
      stderr: String(decoding: stderrData, as: UTF8.self)
    )
  }

  static func throwIfFailed(_ result: ProcessResult, executable: String, check: Bool) throws {
    if check, result.status != 0 {
      let stderr = result.stderr.trimmed
      throw ControllerError.operationFailed(
        stderr.isEmpty
          ? "command failed with exit \(result.status): \(executable)"
          : stderr
      )
    }
  }
}
