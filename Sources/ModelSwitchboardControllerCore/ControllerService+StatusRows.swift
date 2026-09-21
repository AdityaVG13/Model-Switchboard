import Foundation
import ModelSwitchboardCore

extension ControllerService {
  func statusRows(
    names: [String],
    loaded: [String: ControllerProfile],
    conflicts: [String: (String, [String])]
  ) throws -> [ModelProfileStatus] {
    try names.map { name -> ModelProfileStatus in
      guard let profile = loaded[name] else { throw ControllerError.profileNotFound(name) }
      return status(for: profile, allowPortFallback: conflicts[name] == nil)
    }
  }
}
