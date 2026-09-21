import Foundation
import ModelSwitchboardCore

struct DroidSyncService {
  let configuration: ControllerConfiguration
  let profiles: ProfileRepository
  let settingsURL: URL
  let fileManager = FileManager.default

  func sync() throws {
    let managedProfiles = try managedDroidProfiles()
    var settings = try readObject(settingsURL)
    let sets = try droidSyncSets(managedProfiles: managedProfiles)
    settings["customModels"] = try rebuiltCustomModels(
      existing: settings["customModels"] as? [[String: Any]] ?? [],
      sets: sets,
      managedProfiles: managedProfiles
    )
    try write(settings, to: settingsURL)
    try write(
      ["names": sets.managedNames.sorted(), "ids": sets.managedIDs.sorted()], to: configuration.droidStateFile
    )
  }
}
