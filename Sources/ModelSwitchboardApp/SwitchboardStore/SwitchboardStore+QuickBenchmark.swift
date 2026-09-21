import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func quickBenchmark(_ profiles: [String]? = nil) async {
        guard canStartQuickBenchmark else { return }
        let action = benchmarkAction(for: profiles)
        guard pendingGlobalActions.insert(action).inserted else { return }
        activeBenchmarkProfiles = profiles ?? []
        defer {
            pendingGlobalActions.remove(action)
        }
        if await run({ try await $0.quickBenchmark(profiles: profiles) }) {
            markBenchmarkStarted()
        } else {
            activeBenchmarkProfiles = []
        }
    }

    func benchmarkAction(for profiles: [String]?) -> GlobalAction {
        if let profiles, profiles.count == 1, let profile = profiles.first {
            return .benchmark(profile: profile)
        }
        if profiles == nil { return .benchmarkAll }
        return .benchmarkSelected
    }
}
