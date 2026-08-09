import Testing
@testable import ModelSwitchboardApp

@Test func profileHeroStatusCopyLocalWarmingWhenRunningNotReady() {
    #expect(
        ProfileHeroStatusCopy.label(ready: false, running: true, pending: nil, gatewayName: nil)
            == "WARMING"
    )
}

@Test func profileHeroStatusCopyRemoteActive() {
    #expect(
        ProfileHeroStatusCopy.label(ready: true, running: true, pending: nil, gatewayName: "Spark")
            == "ACTIVE ON SPARK"
    )
}

@Test func profileHeroStatusCopyRemoteStartingWhenNotRunning() {
    #expect(
        ProfileHeroStatusCopy.label(ready: false, running: false, pending: nil, gatewayName: "Spark")
            == "STARTING ON SPARK"
    )
}

@Test func profileHeroStatusCopyPrefersPending() {
    #expect(
        ProfileHeroStatusCopy.label(
            ready: true,
            running: true,
            pending: "STARTING",
            gatewayName: "Spark"
        ) == "STARTING ON SPARK"
    )
}
