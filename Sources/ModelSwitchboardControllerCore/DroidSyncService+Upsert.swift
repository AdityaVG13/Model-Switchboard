import Foundation
import ModelSwitchboardCore

extension DroidSyncService {
    func upsertManagedProfile(
        _ profile: ControllerProfile,
        customModels: inout [[String: Any]],
        indexByName: inout [String: Int],
        replacementsByName: [String: [String: Any]],
        maximumIndex: inout Int
    ) throws {
        var entry = try buildEntry(profile)
        entry["id"] = droidID(profile)
        if let index = indexByName[profile.displayName] {
            entry["index"] = customModels[index]["index"] ?? index
            customModels[index] = entry
            return
        }
        let replacement = replacements(profile).compactMap { replacementsByName[$0] }.first
        if let replacement {
            entry["index"] = replacement["index"] ?? maximumIndex + 1
        } else {
            maximumIndex += 1
            entry["index"] = maximumIndex
        }
        indexByName[profile.displayName] = customModels.count
        customModels.append(entry)
    }
}
