import Foundation
import ModelSwitchboardCore

extension ControllerService {
  public func runIntegration(_ id: String, action: String) throws {
    guard id == "droid", action == "sync" else {
      throw ControllerError.unsupported("Unsupported integration action: \(id):\(action)")
    }
    try DroidSyncService(
      configuration: configuration, profiles: profiles, settingsURL: droidSettingsURL
    ).sync()
  }
}
