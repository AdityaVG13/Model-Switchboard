import Foundation
import OSLog
import ModelSwitchboardCore

extension SwitchboardStore {
    /// Local keeps the pre-gateway key strings byte-for-byte; remote gateways
    /// get suffixed keys so their profile names never leak into local state
    /// (e.g. "Reopen Last Active" starting a remote-only profile locally).
    var lastActiveProfilesDefaultsKey: String {
        gateway.isLocal
            ? Constants.lastActiveProfilesKey
            : "\(Constants.lastActiveProfilesKey).\(gateway.id)"
    }

    var benchmarkCooldownDefaultsKey: String {
        gateway.isLocal
            ? Constants.benchmarkCooldownKey
            : "\(Constants.benchmarkCooldownKey).\(gateway.id)"
    }

    func loadCachedState() {
        guard let cached = cachedStateLoader() else { return }
        apply(payload: cached.payload)
        lastUpdated = cached.cachedAt
    }

    func cacheCurrentState() {
        cachePayload(currentPayload, context: "state")
    }

    func cachePayload(_ payload: ControllerStatusPayload, context: String) {
        cachePayloadWriter(payload, context)
    }

    /// Default writer for remote-gateway stores: the shared cache file feeds the
    /// widget and local-controller migration, so remote payloads never touch it.
    nonisolated static func discardCachePayload(_ payload: ControllerStatusPayload, context: String) {}

    nonisolated static func writeCachePayload(_ payload: ControllerStatusPayload, context: String) {
        do {
            try ControllerStatusCache.write(payload)
        } catch {
            let logger = Logger(subsystem: "io.modelswitchboard.app", category: "switchboard-store")
            logger.error("Cache write failed (\(context, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

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
        UserDefaults.standard.set(deduplicated, forKey: lastActiveProfilesDefaultsKey)
    }
}
