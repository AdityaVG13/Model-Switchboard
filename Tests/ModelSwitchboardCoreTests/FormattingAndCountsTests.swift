import Testing
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardCore

@Test func profileRuntimeCountsCountRunningAndReadyProfiles() {
    let counts = ProfileRuntimeCounts(statuses: [
        ModelFixtures.profileStatus(profile: "a", running: true, ready: true),
        ModelFixtures.profileStatus(profile: "b", running: true, ready: false),
        ModelFixtures.profileStatus(profile: "c", running: false, ready: true),
    ])

    #expect(counts.total == 3)
    #expect(counts.running == 2)
    #expect(counts.ready == 2)
}

@Test func durationFormattingRendersCompactCountdown() {
    #expect(DurationFormatting.compactCountdown(remaining: 0) == nil)
    #expect(DurationFormatting.compactCountdown(remaining: 45) == "45s")
    #expect(DurationFormatting.compactCountdown(remaining: 125) == "2m 5s")
}


@Test func profileRuntimeCountsIgnoreSyntheticDiscoveryProfiles() {
    let counts = ProfileRuntimeCounts(statuses: [
        ModelFixtures.profileStatus(profile: "llama", running: true, ready: true),
        ModelFixtures.profileStatus(profile: "port-8000", running: true, ready: true),
        ModelFixtures.profileStatus(profile: "discovered-9000", running: true, ready: true),
    ])

    #expect(counts.total == 1)
    #expect(counts.running == 1)
    #expect(counts.ready == 1)
}


@Test func profileRuntimeCountsPreferSourceOverName() {
    let counts = ProfileRuntimeCounts(statuses: [
        ModelFixtures.profileStatus(profile: "llama", running: true, ready: true, source: "profile"),
        ModelFixtures.profileStatus(profile: "odd-name", running: true, ready: true, source: "discovery"),
        ModelFixtures.profileStatus(profile: "port-like-but-real", running: false, ready: false, source: "profile"),
    ])

    #expect(counts.total == 2)
    #expect(counts.running == 1)
    #expect(counts.ready == 1)
}

@Test func dashboardSummaryPrefersAgentProfileReadyCount() {
    let payload = ModelFixtures.statusPayload(
        statuses: [
            ModelFixtures.profileStatus(profile: "llama", running: true, ready: true, source: "profile"),
            ModelFixtures.profileStatus(profile: "discovered-9", running: true, ready: true, source: "discovery"),
        ],
        profileTotalCount: 1,
        profileReadyCount: 1
    )
    let summary = DashboardSummary(payload: payload)
    #expect(summary.totalProfiles == 1)
    #expect(summary.readyProfiles == 1)
}
