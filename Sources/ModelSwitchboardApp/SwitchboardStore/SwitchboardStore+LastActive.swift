import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func rememberLastActiveProfiles(from sourceStatuses: [ModelProfileStatus]) {
        let runningProfiles = sourceStatuses.boardVisible
            .filter(\.running)
            .map(\.profile)
        guard !runningProfiles.isEmpty else { return }

        var deduplicated: [String] = []
        var seen: Set<String> = []
        for profile in runningProfiles where seen.insert(profile).inserted {
            deduplicated.append(profile)
        }
        lastActiveProfiles = deduplicated
        UserDefaults.standard.set(deduplicated, forKey: lastActiveProfilesDefaultsKey)
    }
}
