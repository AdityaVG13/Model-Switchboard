import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

@Test func profileHeroStatusCopy() {
    let cases: [(ModelProfileStatus.Lifecycle, String?, String?, String)] = [
        (.starting, nil, nil, "WARMING"),
        (.running, nil, "Spark", "ACTIVE ON SPARK"),
        (.stopped, nil, "Spark", "STOPPED ON SPARK"),
        (.running, "STARTING", "Spark", "STARTING ON SPARK"),
    ]
    for value in cases {
        #expect(ProfileHeroStatusCopy.label(
            lifecycle: value.0,
            pending: value.1, gatewayName: value.2
        ) == value.3)
    }
}
