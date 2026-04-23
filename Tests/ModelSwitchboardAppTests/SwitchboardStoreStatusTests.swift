import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

@MainActor
private func makeStore() -> SwitchboardStore {
    SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:8877",
        features: .base,
        autoStartRefresh: false
    )
}

private func makeStatus(running: Bool = true, ready: Bool = true) -> ModelProfileStatus {
    ModelProfileStatus(
        profile: "qwen",
        displayName: "Qwen",
        runtime: "llama.cpp",
        host: "127.0.0.1",
        port: "8080",
        baseURL: "http://127.0.0.1:8080/v1",
        requestModel: "qwen",
        serverModelID: "qwen",
        pid: running ? 42 : nil,
        running: running,
        ready: ready,
        serverIDs: running ? ["qwen"] : [],
        rssMB: running ? 4096 : nil,
        command: nil,
        logPath: "/tmp/qwen.log"
    )
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
