import Foundation
import ModelSwitchboardCore

extension DroidSyncService {
    func filterExistingModels(
        _ existing: [[String: Any]],
        removedNames: Set<String>,
        removedIDs: Set<String>,
        previousNames: Set<String>,
        managedNames: Set<String>,
        replacementNames: Set<String>
    ) -> (customModels: [[String: Any]], replacementsByName: [String: [String: Any]]) {
        var replacementsByName: [String: [String: Any]] = [:]
        var customModels: [[String: Any]] = []
        for model in existing {
            let name = model["displayName"] as? String ?? ""
            let id = model["id"] as? String ?? ""
            if isRemovedExisting(name: name, id: id, removedNames: removedNames, removedIDs: removedIDs) {
                continue
            }
            if isStaleUnmanaged(name: name, previousNames: previousNames, managedNames: managedNames) {
                continue
            }
            if replacementNames.contains(name) {
                replacementsByName[name] = model
                continue
            }
            customModels.append(model)
        }
        return (customModels, replacementsByName)
    }
}
