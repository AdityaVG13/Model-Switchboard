import Darwin
import Foundation

public struct ProcessResult: Sendable, Equatable {
  public let status: Int32
  public let stdout: String
  public let stderr: String
}

public enum ProcessRunner {
  @discardableResult
  public static func run(
    _ executable: String,
    _ arguments: [String] = [],
    environment: [String: String]? = nil,
    currentDirectory: URL? = nil,
    check: Bool = true
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = currentDirectory
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let result = ProcessResult(
      status: process.terminationStatus,
      stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
      stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
    if check, result.status != 0 {
      throw ControllerError.operationFailed(
        result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "command failed with exit \(result.status): \(executable)"
          : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    return result
  }

  public static func processIsAlive(_ pid: Int?) -> Bool {
    guard let pid, pid > 0 else { return false }
    return kill(pid_t(pid), 0) == 0 || errno == EPERM
  }

  public static func signalProcessTree(_ pid: Int, signal: Int32) {
    let processGroup = getpgid(pid_t(pid))
    if processGroup > 0, processGroup != getpgrp() {
      _ = killpg(processGroup, signal)
    }
    if let children = try? run("/usr/bin/pgrep", ["-P", String(pid)], check: false) {
      for child in children.stdout.split(whereSeparator: \.isNewline).compactMap({ Int($0) })
        .reversed()
      {
        signalProcessTree(child, signal: signal)
      }
    }
    _ = kill(pid_t(pid), signal)
  }

  public static func terminate(_ pid: Int, timeout: TimeInterval = 12) {
    signalProcessTree(pid, signal: SIGTERM)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, processIsAlive(pid) {
      Thread.sleep(forTimeInterval: 0.2)
    }
    if processIsAlive(pid) {
      signalProcessTree(pid, signal: SIGKILL)
    }
  }
}
