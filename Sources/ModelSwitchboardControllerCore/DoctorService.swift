import Foundation
import ModelSwitchboardCore

public final class DoctorService: @unchecked Sendable {
  unowned let service: ControllerService
  let fileManager = FileManager.default

  init(service: ControllerService) {
    self.service = service
  }

  func toolVersion() -> String {
    let versionURL = service.configuration.root.deletingLastPathComponent().appendingPathComponent(
      "VERSION")
    return (try? String(contentsOf: versionURL, encoding: .utf8))?.trimmed ?? "dev"
  }

  var doctorRunsDirectory: URL {
    service.configuration.root.deletingLastPathComponent().appendingPathComponent(
      ".doctor/runs", isDirectory: true)
  }

  func sanitizedRunID(_ value: String) throws -> String {
    guard value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
      throw ControllerError.usage("invalid doctor run id")
    }
    return value
  }

  func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "")
      .replacingOccurrences(of: "-", with: "")
  }
}
