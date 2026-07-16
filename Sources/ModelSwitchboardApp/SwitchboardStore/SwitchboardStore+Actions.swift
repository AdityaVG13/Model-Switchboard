import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func activate(_ profile: String) async {
        await runProfileAction(profile, label: "ACTIVATING") {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.activate(profile: profile)
        }
    }

    func start(_ profile: String) async {
        await runProfileAction(profile, label: "STARTING") {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.start(profile: profile)
        }
    }

    func stop(_ profile: String) async {
        await runProfileAction(profile, label: "STOPPING") {
            markProfile(profile, running: false, ready: false)
        } action: {
            try await $0.stop(profile: profile)
        } verify: {
            try await self.verifyProfileStopped(profile, using: $0)
        }
    }

    func restart(_ profile: String) async {
        await runProfileAction(profile, label: "RESTARTING") {
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

    func stopAll() async {
        guard pendingGlobalActions.insert("stop-all").inserted else { return }
        defer { pendingGlobalActions.remove("stop-all") }
        noteManagedLoopbackTransition()
        rememberLastActiveProfiles(from: statuses)
        let stoppingProfiles = Set(statuses.filter { $0.running || $0.ready }.map(\.profile))
        statuses = statuses.map { $0.updating(running: false, ready: false) }
        await run(
            { try await $0.stopAll() },
            verify: { try await self.verifyProfilesStopped(stoppingProfiles, using: $0) }
        )
    }

    func quickBenchmark(_ profiles: [String]? = nil) async {
        guard features.supportsBenchmarks else { return }
        if benchmark?.running == true {
            return
        }
        if benchmarkCooldownRemaining > 0 {
            return
        }
        let key: String
        if let profiles, profiles.count == 1, let profile = profiles.first {
            key = "bench-\(profile)"
        } else if profiles == nil {
            key = "bench-all"
        } else {
            key = "bench-selected"
        }
        guard pendingGlobalActions.insert(key).inserted else { return }
        activeBenchmarkProfiles = profiles ?? []
        defer {
            pendingGlobalActions.remove(key)
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
        guard pendingGlobalActions.insert("reopen-last").inserted else { return }
        defer { pendingGlobalActions.remove("reopen-last") }
        noteManagedLoopbackTransition()

        for profile in profiles {
            pendingProfileActions[profile] = "STARTING"
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
            if isBenignCancellation(error) { return }
            lastError = bootstrapDiagnostic ?? error.localizedDescription
        }
    }
}
