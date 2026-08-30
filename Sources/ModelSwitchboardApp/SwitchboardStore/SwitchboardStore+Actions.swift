import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func activate(_ profile: String) async {
        await runProfileAction(profile, label: .activating) {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.activate(profile: profile)
        }
    }

    func start(_ profile: String) async {
        await runProfileAction(profile, label: .starting) {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.start(profile: profile)
        }
    }

    func stop(_ profile: String) async {
        await runProfileAction(profile, label: .stopping) {
            markProfile(profile, running: false, ready: false)
        } action: {
            try await $0.stop(profile: profile)
        } verify: {
            try await self.verifyProfileStopped(profile, using: $0)
        }
    }

    func restart(_ profile: String) async {
        await runProfileAction(profile, label: .restarting) {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.restart(profile: profile)
        }
    }

    func runIntegration(_ integration: ControllerIntegration, action: String = "sync") async {
        guard features.supportsIntegrations else { return }
        guard pendingIntegrationActions.insert(integration.id).inserted else { return }
        defer { pendingIntegrationActions.remove(integration.id) }
        await run { try await $0.runIntegration(id: integration.id, action: action) }
    }

    func setProfilesDirectory(_ path: String) async {
        _ = await run(
            { try await $0.setProfilesDirectory(path) },
            actionName: "Save profiles folder"
        )
    }

    func stopAll() async {
        guard pendingGlobalActions.insert(.stopAll).inserted else { return }
        defer { pendingGlobalActions.remove(.stopAll) }
        noteManagedLoopbackTransition()
        rememberLastActiveProfiles(from: statuses)
        let previousStatuses = statuses
        let stoppingProfiles = Set(statuses.filter { $0.running || $0.ready }.map(\.profile))
        statuses = statuses.map { $0.updating(running: false, ready: false) }
        let succeeded = await run(
            { try await $0.stopAll() },
            verify: { try await self.verifyProfilesStopped(stoppingProfiles, using: $0) }
        )
        if !succeeded {
            statuses = previousStatuses
        }
    }

    func quickBenchmark(_ profiles: [String]? = nil) async {
        guard features.supportsBenchmarks else { return }
        if benchmark?.running == true {
            return
        }
        if benchmarkCooldownRemaining > 0 {
            return
        }
        let action: GlobalAction
        if let profiles, profiles.count == 1, let profile = profiles.first {
            action = .benchmark(profile: profile)
        } else if profiles == nil {
            action = .benchmarkAll
        } else {
            action = .benchmarkSelected
        }
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

    func reopenLastActive() async {
        guard canReopenLastActive else { return }
        let profiles = lastActiveProfiles
        guard pendingGlobalActions.insert(.reopenLastActive).inserted else { return }
        defer { pendingGlobalActions.remove(.reopenLastActive) }
        noteManagedLoopbackTransition()
        let previousStatuses = statuses

        for profile in profiles {
            pendingProfileActions[profile] = .starting
            markProfile(profile, running: true, ready: false)
        }

        defer {
            for profile in profiles {
                pendingProfileActions.removeValue(forKey: profile)
            }
        }

        do {
            let client = try self.client
            for profile in profiles {
                _ = try await client.start(profile: profile)
            }
            await refresh()
        } catch {
            if isBenignCancellation(error) {
                statuses = previousStatuses
                return
            }
            statuses = previousStatuses
            recordRefreshFailure(error)
        }
    }
}
