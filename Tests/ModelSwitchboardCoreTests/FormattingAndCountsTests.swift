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
        ModelFixtures.profileStatus(profile: "discovered-9000", running: true, ready: true, origin: .discovery),
    ])

    #expect(counts.total == 2)
    #expect(counts.running == 2)
    #expect(counts.ready == 2)
}

@Test func profileRuntimeCountsIncludePortClaimsWithoutSource() {
    let counts = ProfileRuntimeCounts(statuses: [
        ModelFixtures.profileStatus(profile: "port-8027", running: true, ready: false),
    ])

    #expect(counts.total == 1)
    #expect(counts.running == 1)
    #expect(counts.ready == 0)
}

@Test func profileRuntimeCountsTreatClaimSourceAsFileBacked() {
    let counts = ProfileRuntimeCounts(statuses: [
        ModelFixtures.profileStatus(profile: "port-8000", running: true, ready: true, origin: .claim),
        ModelFixtures.profileStatus(profile: "port-9000", running: true, ready: true, origin: .discovery),
        ModelFixtures.profileStatus(profile: "x", running: false, ready: false, origin: .listening),
    ])

    #expect(counts.total == 1)
    #expect(counts.running == 1)
    #expect(counts.ready == 1)
}

@Test func profileRuntimeCountsPreferSourceOverName() {
    let counts = ProfileRuntimeCounts(statuses: [
        ModelFixtures.profileStatus(profile: "llama", running: true, ready: true, origin: .profile),
        ModelFixtures.profileStatus(profile: "odd-name", running: true, ready: true, origin: .discovery),
        ModelFixtures.profileStatus(profile: "port-like-but-real", running: false, ready: false, origin: .profile),
    ])

    #expect(counts.total == 2)
    #expect(counts.running == 1)
    #expect(counts.ready == 1)
}

@Test func profileRuntimeCountsMatchBoardVisibility() {
    let counts = ProfileRuntimeCounts(statuses: [
        ModelFixtures.profileStatus(
            profile: "stale-flat",
            running: false,
            ready: false,
            origin: .profile,
            missingArtifacts: ["/tmp/gone.gguf"]
        ),
        ModelFixtures.profileStatus(
            profile: "port-8027",
            running: false,
            ready: false,
            origin: .claim,
            missingArtifacts: ["/tmp/gone.gguf"]
        ),
        ModelFixtures.profileStatus(
            profile: "alive",
            running: true,
            ready: true,
            origin: .profile
        ),
    ])
    #expect(counts.total == 2)
    #expect(counts.running == 1)
    #expect(counts.ready == 1)
}
