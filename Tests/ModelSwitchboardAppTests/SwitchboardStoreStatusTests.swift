import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

@MainActor
private func makeStore(
    loopbackEndpointProbe: SwitchboardStore.LoopbackEndpointProbe? = nil
) -> SwitchboardStore {
    SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:8877",
        features: .base,
        autoStartRefresh: false,
        loopbackEndpointProbe: loopbackEndpointProbe
    )
}

private func makeStatus(
    profile: String = "qwen",
    displayName: String = "Qwen",
    host: String = "127.0.0.1",
    port: String = "8080",
    baseURL: String = "http://127.0.0.1:8080/v1",
    running: Bool = true,
    ready: Bool = true
) -> ModelProfileStatus {
    ModelProfileStatus(
        profile: profile,
        displayName: displayName,
        runtime: "llama.cpp",
        host: host,
        port: port,
        baseURL: baseURL,
        requestModel: profile,
        serverModelID: profile,
        pid: running ? 42 : nil,
        running: running,
        ready: ready,
        serverIDs: running ? [profile] : [],
        rssMB: running ? 4096 : nil,
        command: nil,
        logPath: "/tmp/qwen.log"
    )
}

actor ProbeRecorder {
    private(set) var calls = 0

    func record(_ profiles: [ModelProfileStatus]) -> [String] {
        calls += 1
        return profiles.map(\.profile)
    }
}

@MainActor
@Test func staleRunningStateIsHiddenFromLiveCounts() {
    let store = makeStore()
    let now = Date(timeIntervalSince1970: 200)
    let staleDate = now.addingTimeInterval(-60)
    let status = makeStatus()

    store.statuses = [status]
    store.lastUpdated = staleDate

    #expect(store.statusFreshness(relativeTo: now) == .stale)
    #expect(store.displayedRunningProfiles(relativeTo: now) == 0)
    #expect(store.displayedReadyProfiles(relativeTo: now) == 0)
    #expect(store.profileBadgeState(for: status, relativeTo: now) == .stale)
    #expect(store.menuBarHelp(relativeTo: now).localizedCaseInsensitiveContains("stale"))
}

@MainActor
@Test func cachedStateIsReportedDistinctly() {
    let store = makeStore()
    let now = Date(timeIntervalSince1970: 200)
    let status = makeStatus()

    store.statuses = [status]
    store.lastUpdated = now
    store.lastError = "Controller unavailable. Showing cached state."

    #expect(store.statusFreshness(relativeTo: now) == .cached)
    #expect(store.profileBadgeState(for: status, relativeTo: now) == .stale)
    #expect(store.menuBarHelp(relativeTo: now).localizedCaseInsensitiveContains("cached"))
}

@MainActor
@Test func freshStateKeepsLiveCountsAndRunningBadge() {
    let store = makeStore()
    let now = Date(timeIntervalSince1970: 200)
    let status = makeStatus()

    store.statuses = [status]
    store.lastUpdated = now

    #expect(store.statusFreshness(relativeTo: now) == .fresh)
    #expect(store.displayedRunningProfiles(relativeTo: now) == 1)
    #expect(store.displayedReadyProfiles(relativeTo: now) == 1)
    #expect(store.profileBadgeState(for: status, relativeTo: now) == .running)
    #expect(store.menuBarHelp(relativeTo: now) == "Running: Qwen")
}

@MainActor
@Test func loopbackProbeClearsDeadReadyProfilesImmediately() async throws {
    let store = makeStore { _ in
        ["qwen"]
    }
    let now = Date(timeIntervalSince1970: 200)

    store.statuses = [makeStatus()]
    store.lastUpdated = now

    await store.probeLoopbackEndpointsIfNeeded()

    let status = try #require(store.statuses.first)
    #expect(status.running == false)
    #expect(status.ready == false)
    #expect(status.pid == nil)
    #expect(status.serverIDs.isEmpty)
    #expect(status.rssMB == nil)
    #expect(store.displayedRunningProfiles(relativeTo: now) == 0)
    #expect(store.displayedReadyProfiles(relativeTo: now) == 0)
    #expect(store.menuBarHelp(relativeTo: now) == "No local models running")
}

@MainActor
@Test func loopbackProbeSkipsPendingAndRemoteProfiles() async {
    let recorder = ProbeRecorder()
    let store = makeStore { profiles in
        _ = await recorder.record(profiles)
        return []
    }

    store.statuses = [
        makeStatus(profile: "pending"),
        makeStatus(
            profile: "remote",
            displayName: "Remote",
            host: "10.0.0.8",
            port: "8081",
            baseURL: "http://10.0.0.8:8081/v1"
        ),
    ]
    store.pendingProfileActions["pending"] = "STARTING"

    await store.probeLoopbackEndpointsIfNeeded()

    #expect(await recorder.calls == 0)
    #expect(store.statuses.filter(\.running).count == 2)
    #expect(store.statuses.filter(\.ready).count == 2)
}

@MainActor
@Test func loopbackProbeUsesFastThenSteadyCadence() {
    let store = makeStore()
    let now = Date(timeIntervalSince1970: 200)

    store.statuses = [makeStatus()]
    store.armLoopbackEndpointProbeFastWindow(relativeTo: now)

    #expect(store.shouldProbeLoopbackEndpoints(relativeTo: now) == true)
    #expect(store.nextLoopbackEndpointProbeInterval(relativeTo: now) == 2)
    #expect(store.nextLoopbackEndpointProbeInterval(relativeTo: now.addingTimeInterval(31)) == 5)
}

@MainActor
@Test func loopbackProbeSuppressionSkipsManagedWindow() async {
    let recorder = ProbeRecorder()
    let store = makeStore { profiles in
        _ = await recorder.record(profiles)
        return []
    }
    let now = Date(timeIntervalSince1970: 200)

    store.statuses = [makeStatus()]
    store.suppressLoopbackEndpointProbe(relativeTo: now)

    #expect(store.shouldProbeLoopbackEndpoints(relativeTo: now) == false)
    #expect(store.nextLoopbackEndpointProbeInterval(relativeTo: now) == 4)

    await store.probeLoopbackEndpointsIfNeeded(relativeTo: now)

    #expect(await recorder.calls == 0)
    #expect(store.shouldProbeLoopbackEndpoints(relativeTo: now.addingTimeInterval(5)) == true)
}
