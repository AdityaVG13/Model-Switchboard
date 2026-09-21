import Foundation
import OSLog
import ModelSwitchboardCore

extension SwitchboardStore {
    func loadLastActiveProfiles() {
        lastActiveProfiles = UserDefaults.standard.stringArray(forKey: lastActiveProfilesDefaultsKey) ?? []
    }

    func loadBenchmarkCooldownState() {
        guard let timestamp = UserDefaults.standard.object(forKey: benchmarkCooldownDefaultsKey) as? TimeInterval else {
            lastBenchmarkStartedAt = nil
            return
        }
        lastBenchmarkStartedAt = Date(timeIntervalSince1970: timestamp)
    }

    func loadAutoBenchmarkedProfiles() {
        let stored = UserDefaults.standard.stringArray(forKey: autoBenchmarkedProfilesDefaultsKey) ?? []
        autoBenchmarkedProfiles = Set(stored)
    }

    func persistAutoBenchmarkedProfiles() {
        UserDefaults.standard.set(
            Array(autoBenchmarkedProfiles).sorted(),
            forKey: autoBenchmarkedProfilesDefaultsKey
        )
    }

    func markAutoBenchmarked(_ profile: String) {
        guard autoBenchmarkedProfiles.insert(profile).inserted else { return }
        persistAutoBenchmarkedProfiles()
    }
}
