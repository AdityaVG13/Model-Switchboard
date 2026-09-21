import Foundation
import OSLog
import ModelSwitchboardCore

extension SwitchboardStore {
    /// Local keeps the pre-gateway key strings byte-for-byte; remote gateways
    /// get suffixed keys so their profile names never leak into local state
    /// (e.g. "Reopen Last Active" starting a remote-only profile locally).
    func gatewayScopedDefaultsKey(_ base: String) -> String {
        gateway.isLocal ? base : "\(base).\(gateway.id)"
    }

    var lastActiveProfilesDefaultsKey: String {
        gatewayScopedDefaultsKey(Constants.lastActiveProfilesKey)
    }

    var benchmarkCooldownDefaultsKey: String {
        gatewayScopedDefaultsKey(Constants.benchmarkCooldownKey)
    }

    var autoBenchmarkedProfilesDefaultsKey: String {
        gatewayScopedDefaultsKey(Constants.autoBenchmarkedProfilesKey)
    }

    func loadCachedState() {
        guard let cached = cachedStateLoader() else { return }
        apply(payload: cached.payload, considerAutoBenchmark: false)
        lastUpdated = cached.cachedAt
    }

    func loadPersistedState() {
        loadLastActiveProfiles()
        loadBenchmarkCooldownState()
        loadAutoBenchmarkedProfiles()
        loadCachedState()
    }
}
