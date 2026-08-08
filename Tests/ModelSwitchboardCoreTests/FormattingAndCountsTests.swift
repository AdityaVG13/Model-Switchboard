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
