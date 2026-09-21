import Foundation
import ModelSwitchboardCore

extension ControllerService {
  public func integrationStatus() -> [ControllerIntegration] {
    let droidExists =
      fileManager.fileExists(atPath: droidSettingsURL.path)
      || (try? ProcessRunner.run("/usr/bin/which", ["droid"], check: false).status) == 0
    guard droidExists else { return [] }
    return [
      ControllerIntegration(
        id: "droid",
        displayName: "Factory Droid",
        kind: .modelRegistry,
        capabilities: ["sync"],
        syncLabel: "Sync Droid",
        description: "Sync managed local profiles into Factory Droid custom model settings."
      )
    ]
  }
}
