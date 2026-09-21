import Darwin
import Foundation
import ModelSwitchboardCore

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
    let result = finish(process, stdout: stdout, stderr: stderr)
    try throwIfFailed(result, executable: executable, check: check)
    return result
  }
}
