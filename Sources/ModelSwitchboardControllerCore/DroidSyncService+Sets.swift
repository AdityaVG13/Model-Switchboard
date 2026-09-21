import Foundation
import ModelSwitchboardCore

extension DroidSyncService {
  func droidSyncSets(managedProfiles: [ControllerProfile]) throws -> (
    previousNames: Set<String>,
    removedNames: Set<String>,
    removedIDs: Set<String>,
    managedNames: Set<String>,
    managedIDs: Set<String>,
    replacementNames: Set<String>
  ) {
    let previous = try readObject(configuration.droidStateFile)
    let removed = try readObject(configuration.droidRemovedStateFile)
    return (
      previousNames: Set(previous["names"] as? [String] ?? []),
      removedNames: Set(removed["names"] as? [String] ?? []),
      removedIDs: Set(removed["ids"] as? [String] ?? []),
      managedNames: Set(managedProfiles.map(\.displayName)),
      managedIDs: Set(managedProfiles.map(droidID)),
      replacementNames: Set(managedProfiles.flatMap { replacements($0) })
    )
  }
}
