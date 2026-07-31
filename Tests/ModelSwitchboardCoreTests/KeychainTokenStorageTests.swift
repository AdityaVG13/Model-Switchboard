import Foundation
import Testing
@testable import ModelSwitchboardCore

private func makeStorage(account: String = KeychainTokenStorage.legacyAccount) -> KeychainTokenStorage {
    KeychainTokenStorage(
        service: "io.modelswitchboard.tests.\(UUID().uuidString)",
        accessGroup: nil,
        account: account
    )
}

@Test func saveThenLoadRoundTripsToken() {
    let storage = makeStorage()
    defer { storage.delete() }

    storage.save("first-token-value-0123456789")
    #expect(storage.load() == "first-token-value-0123456789")
}

@Test func savingAgainOverwritesExistingToken() {
    let storage = makeStorage()
    defer { storage.delete() }

    storage.save("first-token-value-0123456789")
    storage.save("second-token-value-987654321")
    #expect(storage.load() == "second-token-value-987654321")
}

@Test func savingEmptyTokenDeletesExistingItem() {
    let storage = makeStorage()
    defer { storage.delete() }

    storage.save("first-token-value-0123456789")
    storage.save("   ")
    #expect(storage.load() == nil)
}

@Test func distinctAccountsAreIsolatedWithinOneService() {
    let service = "io.modelswitchboard.tests.\(UUID().uuidString)"
    let local = KeychainTokenStorage(service: service, accessGroup: nil)
    let gateway = KeychainTokenStorage(service: service, accessGroup: nil, account: "gateway-abc")
    defer {
        local.delete()
        gateway.delete()
    }

    local.save("local-token-value-0123456789")
    gateway.save("gateway-token-value-0123456789")

    #expect(local.load() == "local-token-value-0123456789")
    #expect(gateway.load() == "gateway-token-value-0123456789")

    gateway.delete()
    #expect(gateway.load() == nil)
    #expect(local.load() == "local-token-value-0123456789")
}
