import Testing
@testable import ModelSwitchboardCore

@Test func companionBundleIdentifierMapsBaseToPlus() {
    #expect(
        LoginItemBundleIdentifiers.companion(for: "io.modelswitchboard.app") == "io.modelswitchboard.plus"
    )
}

@Test func companionBundleIdentifierMapsPlusToBase() {
    #expect(
        LoginItemBundleIdentifiers.companion(for: "io.modelswitchboard.plus") == "io.modelswitchboard.app"
    )
}

@Test func companionBundleIdentifierMappingIsBidirectional() {
    let base = "io.modelswitchboard.app"
    let plus = "io.modelswitchboard.plus"

    let mappedFromBase = LoginItemBundleIdentifiers.companion(for: base)
    let mappedFromPlus = LoginItemBundleIdentifiers.companion(for: plus)

    #expect(mappedFromBase == plus)
    #expect(mappedFromPlus == base)
    #expect(mappedFromBase.flatMap(LoginItemBundleIdentifiers.companion(for:)) == base)
    #expect(mappedFromPlus.flatMap(LoginItemBundleIdentifiers.companion(for:)) == plus)
}

@Test func companionBundleIdentifierReturnsNilForUnknownSuffix() {
    #expect(LoginItemBundleIdentifiers.companion(for: "io.modelswitchboard.desktop") == nil)
}
