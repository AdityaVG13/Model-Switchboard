import Foundation

/// Controller-wide failures. Lives here so JSON, process, and profile code
/// can throw without depending on argv parsing or HTTP routing.
public enum ControllerError: Error, CustomStringConvertible, Sendable {
  case usage(String)
  case invalidConfiguration(String)
  case invalidProfile(String)
  case profileNotFound(String)
  case profileConflict(String)
  case operationFailed(String)
  case unsupported(String)

  public var description: String {
    switch self {
    case .usage(let message), .invalidConfiguration(let message), .invalidProfile(let message),
      .profileConflict(let message), .operationFailed(let message), .unsupported(let message):
      return message
    case .profileNotFound(let name):
      return "Unknown profile: \(name)"
    }
  }
}
