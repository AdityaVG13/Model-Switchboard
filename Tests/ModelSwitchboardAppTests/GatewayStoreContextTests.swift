import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

private let remoteContext = GatewayContext(id: "gw-test", name: "Spark", isLocal: false)

@MainActor
private func makeRemoteStore(
    loopbackEndpointProbe: SwitchboardStore.LoopbackEndpointProbe? = nil,
    controllerClientFactory: SwitchboardStore.ControllerClientFactory? = nil
) -> SwitchboardStore {
    SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9911",
        features: .base,
        gateway: remoteContext,
        autoStartRefresh: false,
        loopbackEndpointProbe: loopbackEndpointProbe,
        controllerClientFactory: controllerClientFactory
            ?? { try ControllerClient(baseURLString: $0, authToken: $1) }
    )
}

@MainActor
@Test func remoteStoreSkipsLoopbackEndpointProbe() async {
    let recorder = ProbeRecorder()
    let store = makeRemoteStore { profiles in
        _ = await recorder.record(profiles)
        return []
    }

    // Remote agents report loopback URLs that are only loopback on the remote
    // host; the store must never probe them from this Mac.
    store.statuses = [ModelFixtures.profileStatus()]
    store.lastUpdated = .now

    await store.probeLoopbackEndpointsIfNeeded()
    #expect(await recorder.calls == 0)
    #expect(store.statuses.filter(\.running).count == 1)

    store.startLoopbackEndpointProbe()
    #expect(store.loopbackEndpointProbeTask == nil)
}

@MainActor
@Test func remoteStoreStaysEmptyWhenRefreshFailsWithoutCache() async {
    let store = makeRemoteStore(controllerClientFactory: { _, _ in
        struct Boom: Error {}
        throw Boom()
    })

    await store.refresh()

    // A remote store must not fall back to the local gateway's cache file.
    #expect(store.statuses.isEmpty)
    #expect(store.lastError != nil)
    #expect(store.lastError?.contains("cached") != true)
}

@MainActor
@Test func remoteStoreNamespacesLastActiveProfilesKey() {
    let legacyKey = "modelswitchboard.last-active-profiles"
    let namespacedKey = "\(legacyKey).gw-test"
    let defaults = UserDefaults.standard
    let savedLegacy = defaults.stringArray(forKey: legacyKey)
    defaults.removeObject(forKey: legacyKey)
    defer {
        defaults.removeObject(forKey: namespacedKey)
        if let savedLegacy {
            defaults.set(savedLegacy, forKey: legacyKey)
        } else {
            defaults.removeObject(forKey: legacyKey)
        }
    }

    let store = makeRemoteStore()
    #expect(store.lastActiveProfilesDefaultsKey == namespacedKey)
    #expect(store.benchmarkCooldownDefaultsKey == "modelswitchboard.last-benchmark-started-at.gw-test")

    store.rememberLastActiveProfiles(from: [ModelFixtures.profileStatus(profile: "spark-only")])

    #expect(defaults.stringArray(forKey: namespacedKey) == ["spark-only"])
    #expect(defaults.stringArray(forKey: legacyKey) == nil)
}

@MainActor
@Test func localStoreKeepsLegacyDefaultsKeys() {
    let store = SwitchboardStore(
        controllerBaseURL: ControllerEndpointDefaults.baseURLString,
        features: .base,
        autoStartRefresh: false
    )
    #expect(store.gateway == .local)
    #expect(store.lastActiveProfilesDefaultsKey == "modelswitchboard.last-active-profiles")
    #expect(store.benchmarkCooldownDefaultsKey == "modelswitchboard.last-benchmark-started-at")
}
