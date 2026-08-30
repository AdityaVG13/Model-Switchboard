import Testing
@testable import ModelSwitchboardApp

@Test func profileHeroStatusCopy() {
    let cases: [(ready: Bool, running: Bool, pending: String?, gateway: String?, expected: String)] = [
        (false, true, nil, nil, "WARMING"),
        (true, true, nil, "Spark", "ACTIVE ON SPARK"),
        (false, false, nil, "Spark", "STARTING ON SPARK"),
        (true, true, "STARTING", "Spark", "STARTING ON SPARK"),
    ]
    for value in cases {
        #expect(ProfileHeroStatusCopy.label(
            ready: value.ready, running: value.running,
            pending: value.pending, gatewayName: value.gateway
        ) == value.expected)
    }
}
