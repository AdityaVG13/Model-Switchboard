import Foundation
import ModelSwitchboardCore

extension DroidSyncService {
    func isRemovedExisting(
        name: String,
        id: String,
        removedNames: Set<String>,
        removedIDs: Set<String>
    ) -> Bool {
        removedNames.contains(name) || removedIDs.contains(id)
    }

    func isStaleUnmanaged(
        name: String,
        previousNames: Set<String>,
        managedNames: Set<String>
    ) -> Bool {
        previousNames.contains(name) && !managedNames.contains(name)
    }

    func firstIndexByDisplayName(_ customModels: [[String: Any]]) -> [String: Int] {
        var indexByName: [String: Int] = [:]
        for (index, model) in customModels.enumerated() {
            guard let name = model["displayName"] as? String else { continue }
            // Keep the first occurrence - duplicate display names must not trap.
            if indexByName[name] == nil {
                indexByName[name] = index
            }
        }
        return indexByName
    }
}
