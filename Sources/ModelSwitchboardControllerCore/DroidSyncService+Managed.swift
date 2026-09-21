import Foundation
import ModelSwitchboardCore

extension DroidSyncService {
  func managedDroidProfiles() throws -> [ControllerProfile] {
    try profiles.load().values.filter { $0["SYNC_TO_DROID"] == "1" }.sorted {
      $0.name < $1.name
    }
  }
}
