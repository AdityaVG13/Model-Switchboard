import Foundation
import OSLog
import ModelSwitchboardCore

extension SwitchboardStore {
    func loadCachedState() {
        guard let cached = ControllerStatusCache.load() else { return }
        apply(payload: cached.payload)
        lastUpdated = cached.cachedAt
    }

    func cacheCurrentState() {
        cachePayload(currentPayload, context: "state")
    }

    func cachePayload(_ payload: ControllerStatusPayload, context: String) {
        cachePayloadWriter(payload, context)
    }

    nonisolated static func writeCachePayload(_ payload: ControllerStatusPayload, context: String) {
        do {
            try ControllerStatusCache.write(payload)
        } catch {
            let logger = Logger(subsystem: "io.modelswitchboard.app", category: "switchboard-store")
            logger.error("Cache write failed (\(context, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

    func loadLastActiveProfiles() {
        lastActiveProfiles = UserDefaults.standard.stringArray(forKey: Constants.lastActiveProfilesKey) ?? []
    }

    func loadBenchmarkCooldownState() {
        guard let timestamp = UserDefaults.standard.object(forKey: Constants.benchmarkCooldownKey) as? TimeInterval else {
            lastBenchmarkStartedAt = nil
            return
        }
        lastBenchmarkStartedAt = Date(timeIntervalSince1970: timestamp)
    }

    func rememberLastActiveProfiles(from sourceStatuses: [ModelProfileStatus]) {
        let runningProfiles = sourceStatuses
            .filter(\.running)
            .map(\.profile)
        guard !runningProfiles.isEmpty else { return }

        var deduplicated: [String] = []
        var seen: Set<String> = []
        for profile in runningProfiles where seen.insert(profile).inserted {
            deduplicated.append(profile)
        }
        lastActiveProfiles = deduplicated
        UserDefaults.standard.set(deduplicated, forKey: Constants.lastActiveProfilesKey)
    }
}
