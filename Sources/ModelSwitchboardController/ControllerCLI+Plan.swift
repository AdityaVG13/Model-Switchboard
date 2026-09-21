import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
  static func exitCode(for error: Error) -> Int32 {
    guard let controllerError = error as? ControllerError else { return 1 }
    switch controllerError {
    case .usage: return 64
    case .profileConflict: return 5
    case .invalidConfiguration: return 4
    default: return 1
    }
  }

  static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func printPlan(command: String, profiles: [String]) throws {
    try printJSONObject([
      "schema_version": "1",
      "tool": "ModelSwitchboardController",
      "command": command,
      "dry_run": true,
      "status": "planned",
      "plan": profiles.map { ["action": command, "profile": $0] },
      "results": [],
    ])
  }
}
