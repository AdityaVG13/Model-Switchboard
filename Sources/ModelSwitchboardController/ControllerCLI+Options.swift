import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
  static func positionalValues(_ arguments: [String], after command: String) -> [String] {
    guard let commandIndex = arguments.firstIndex(of: command) else { return [] }
    let optionsWithValues = Set([
      "--root", "--host", "--unsafe-bind", "--port", "--auth-token", "--auth-token-file", "--suite",
      "--profiles", "--profile-file", "--run-id",
    ])
    var result: [String] = []
    var skipNext = false
    for argument in arguments.dropFirst(commandIndex + 1) {
      if skipNext {
        skipNext = false
        continue
      }
      if optionsWithValues.contains(argument) {
        skipNext = true
        continue
      }
      if argument.hasPrefix("-") { continue }
      result.append(argument)
    }
    return result
  }

  static func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  static func value(after token: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: token), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  static func isDryRun(_ arguments: [String]) -> Bool {
    arguments.contains("--dry-run") || arguments.contains("--plan")
  }
}
