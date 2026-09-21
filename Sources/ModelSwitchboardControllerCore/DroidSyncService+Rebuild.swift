import Foundation
import ModelSwitchboardCore

extension DroidSyncService {
  func rebuiltCustomModels(
    existing: [[String: Any]],
    sets: (
      previousNames: Set<String>,
      removedNames: Set<String>,
      removedIDs: Set<String>,
      managedNames: Set<String>,
      managedIDs: Set<String>,
      replacementNames: Set<String>
    ),
    managedProfiles: [ControllerProfile]
  ) throws -> [[String: Any]] {
    let filtered = filterExistingModels(
      existing,
      removedNames: sets.removedNames,
      removedIDs: sets.removedIDs,
      previousNames: sets.previousNames,
      managedNames: sets.managedNames,
      replacementNames: sets.replacementNames
    )
    var customModels = filtered.customModels
    var indexByName = firstIndexByDisplayName(customModels)
    var maximumIndex = customModels.compactMap { ($0["index"] as? NSNumber)?.intValue }.max() ?? -1
    for profile in managedProfiles {
      try upsertManagedProfile(
        profile,
        customModels: &customModels,
        indexByName: &indexByName,
        replacementsByName: filtered.replacementsByName,
        maximumIndex: &maximumIndex
      )
    }
    return customModels
  }
}
