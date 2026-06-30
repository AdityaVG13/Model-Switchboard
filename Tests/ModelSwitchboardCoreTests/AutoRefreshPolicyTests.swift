import Testing
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardCore

@Test func autoRefreshPolicyUsesIdleCadenceWhenNothingIsLive() {
    let payload = ModelFixtures.statusPayload(
        statuses: [
            ModelFixtures.profileStatus(
                profile: "idle",
                displayName: "Idle",
                pid: nil,
                running: false,
                ready: false,
                rssMB: nil
            )
        ]
    )

    let policy = AutoRefreshPolicy(payload: payload)

    #expect(policy.mode == .idle)
    #expect(policy.interval == AutoRefreshPolicy.idleInterval)
}

@Test func autoRefreshPolicyUsesActiveCadenceForLiveEndpoints() {
    let payload = ModelFixtures.statusPayload(
        statuses: [
            ModelFixtures.profileStatus(
                profile: "active",
                displayName: "Active",
                port: "8081",
                baseURL: "http://127.0.0.1:8081/v1"
            )
        ]
    )

    let policy = AutoRefreshPolicy(payload: payload)

    #expect(policy.mode == .activeRuntime)
    #expect(policy.interval == AutoRefreshPolicy.activeRuntimeInterval)
}

@Test func autoRefreshPolicyPrioritizesBenchmarksAndPendingActions() {
    let payload = ModelFixtures.statusPayload(
        statuses: [
            ModelFixtures.profileStatus(
                profile: "bench",
                displayName: "Bench",
                port: "8082",
                baseURL: "http://127.0.0.1:8082/v1",
                pid: 456,
                running: true,
                ready: false,
                rssMB: nil
            )
        ],
        benchmark: BenchmarkStatus(running: true, pid: 99, logPath: "/tmp/bench-run.log", latest: nil)
    )

    let benchmarkingPolicy = AutoRefreshPolicy(payload: payload)
    let pendingPolicy = AutoRefreshPolicy(payload: payload, hasPendingActions: true)

    #expect(benchmarkingPolicy.mode == .benchmarking)
    #expect(benchmarkingPolicy.interval == AutoRefreshPolicy.benchmarkingInterval)
    #expect(pendingPolicy.mode == .pendingAction)
    #expect(pendingPolicy.interval == AutoRefreshPolicy.pendingActionInterval)
}
