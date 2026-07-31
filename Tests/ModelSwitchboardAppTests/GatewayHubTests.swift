import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

private struct TestBoom: Error {}

@MainActor
private func makeLocalStore() -> SwitchboardStore {
    SwitchboardStore(
        controllerBaseURL: ControllerEndpointDefaults.baseURLString,
        features: .base,
        autoStartRefresh: false,
        controllerClientFactory: { _, _ in throw TestBoom() }
    )
}

@MainActor
private func makeHub(
    defaults: UserDefaults,
    keychainService: String,
    autoStartRemoteRefresh: Bool = false
) -> GatewayHub {
    GatewayHub(
        localStore: makeLocalStore(),
        defaults: defaults,
        remoteStoreFactory: { config, baseURL, token in
            SwitchboardStore(
                controllerBaseURL: baseURL,
                controllerAuthToken: token,
                features: .base,
                gateway: GatewayContext(config: config),
                autoStartRefresh: autoStartRemoteRefresh,
                controllerClientFactory: { _, _ in throw TestBoom() }
            )
        },
        tokenStorageFactory: { id in
            KeychainTokenStorage(service: keychainService, accessGroup: nil, account: "gateway-\(id)")
        },
        sshExecutableURL: URL(fileURLWithPath: "/usr/bin/true")
    )
}

@MainActor
private func withTestDefaults(_ body: @MainActor (UserDefaults, String) throws -> Void) rethrows {
    let suiteName = "io.modelswitchboard.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = "io.modelswitchboard.tests.\(UUID().uuidString)"
    try body(defaults, service)
}

@MainActor
@Test func upsertPersistsConfigAndTokenAndBuildsRuntime() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        #expect(hub.remoteRuntimes.isEmpty)
        #expect(hub.hasRemoteGateways == false)

        let config = GatewayConfig(name: "Lab", kind: .direct, baseURL: "http://10.0.0.9:8877")
        hub.upsertGateway(config, token: "lab-token-0123456789abcdef")
        defer { hub.removeGateway(id: config.id) }

        #expect(hub.remoteRuntimes.count == 1)
        #expect(hub.hasRemoteGateways)
        #expect(GatewayConfigStore.load(from: defaults) == [config])
        #expect(hub.authToken(forGateway: config.id) == "lab-token-0123456789abcdef")

        let runtime = try #require(hub.remoteRuntimes.first)
        #expect(runtime.store.controllerBaseURL == "http://10.0.0.9:8877")
        #expect(runtime.store.controllerAuthToken == "lab-token-0123456789abcdef")
        #expect(runtime.store.gateway.isLocal == false)
    }
}

@MainActor
@Test func removingGatewayCancelsRefreshAndDeletesToken() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service, autoStartRemoteRefresh: true)
        let config = GatewayConfig(name: "Lab", kind: .direct, baseURL: "http://10.0.0.9:8877")
        hub.upsertGateway(config, token: "lab-token-0123456789abcdef")

        let runtime = try #require(hub.remoteRuntimes.first)
        #expect(runtime.store.refreshTask != nil)

        hub.removeGateway(id: config.id)

        // The refresh task holds a strong self reference; teardown must cancel
        // it or the removed store polls a dead endpoint forever.
        #expect(runtime.store.refreshTask == nil)
        #expect(hub.remoteRuntimes.isEmpty)
        #expect(GatewayConfigStore.load(from: defaults).isEmpty)
        #expect(hub.authToken(forGateway: config.id).isEmpty)
    }
}

@MainActor
@Test func editingGatewayRebuildsRuntimeKeepingOthers() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        var first = GatewayConfig(name: "Lab", kind: .direct, baseURL: "http://10.0.0.9:8877")
        let second = GatewayConfig(name: "Attic", kind: .direct, baseURL: "http://10.0.0.7:8877")
        hub.upsertGateway(first, token: "")
        hub.upsertGateway(second, token: "")
        defer {
            hub.removeGateway(id: first.id)
            hub.removeGateway(id: second.id)
        }

        let untouched = try #require(hub.remoteRuntimes.first { $0.id == second.id })

        first.baseURL = "http://10.0.0.10:8877"
        hub.upsertGateway(first, token: "")

        let rebuilt = try #require(hub.remoteRuntimes.first { $0.id == first.id })
        #expect(rebuilt.store.controllerBaseURL == "http://10.0.0.10:8877")
        // Unchanged gateways keep their runtime (and its running store) intact.
        #expect(hub.remoteRuntimes.first { $0.id == second.id } === untouched)
    }
}

@MainActor
@Test func aggregatesSumAcrossGateways() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig(name: "Spark", kind: .direct, baseURL: "http://10.0.0.9:8877")
        hub.upsertGateway(config, token: "")
        defer { hub.removeGateway(id: config.id) }

        let now = Date.now
        hub.localStore.statuses = [
            ModelFixtures.profileStatus(profile: "local-a"),
            ModelFixtures.profileStatus(profile: "local-b", running: false, ready: false),
        ]
        hub.localStore.lastUpdated = now

        let remote = try #require(hub.remoteRuntimes.first)
        remote.store.statuses = [
            ModelFixtures.profileStatus(profile: "spark-a"),
            ModelFixtures.profileStatus(profile: "spark-b"),
        ]
        remote.store.lastUpdated = now

        #expect(hub.totalProfiles == 4)
        #expect(hub.displayedReadyProfiles == 3)
        #expect(hub.displayedRunningProfiles == 3)
        #expect(hub.menuBarHelp.contains("This Mac: 1/2 ready"))
        #expect(hub.menuBarHelp.contains("Spark: 2/2 ready"))
    }
}

@MainActor
@Test func tunnelFailureRoutesDiagnosticToThatStoreOnly() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig(name: "Spark", kind: .ssh, sshUser: "a", sshHost: "spark.invalid")
        hub.upsertGateway(config, token: "")
        defer { hub.removeGateway(id: config.id) }

        hub.tunnelStateChanged(gatewayID: config.id, state: .failed("SSH auth failed."))

        let runtime = try #require(hub.remoteRuntimes.first)
        #expect(runtime.tunnelState == .failed("SSH auth failed."))
        #expect(runtime.store.lastError == "SSH auth failed.")
        #expect(hub.localStore.lastError == nil)
    }
}

@MainActor
@Test func tunnelEstablishedStartsRemoteRefresh() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig(name: "Spark", kind: .ssh, sshUser: "a", sshHost: "spark.invalid")
        hub.upsertGateway(config, token: "")
        defer { hub.removeGateway(id: config.id) }

        let runtime = try #require(hub.remoteRuntimes.first)
        #expect(runtime.store.refreshTask == nil)

        hub.tunnelStateChanged(gatewayID: config.id, state: .established)
        #expect(runtime.store.refreshTask != nil)
    }
}

@MainActor
@Test func reachableEndpointURLHonorsForwardsAndDirectHosts() {
    let sshConfig = GatewayConfig(name: "Spark", kind: .ssh, sshUser: "a", sshHost: "spark")
    let sshStore = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9999",
        features: .base,
        gateway: GatewayContext(config: sshConfig),
        autoStartRefresh: false
    )
    let sshRuntime = GatewayRuntime(config: sshConfig, store: sshStore, tunnel: nil)
    let status = ModelFixtures.profileStatus(
        profile: "qwen", port: "8081", baseURL: "http://127.0.0.1:8081/v1"
    )

    #expect(sshRuntime.reachableEndpointURL(for: status) == nil)
    sshRuntime.forwardedPorts = [8081]
    #expect(sshRuntime.reachableEndpointURL(for: status) == "http://127.0.0.1:8081/v1")

    let directConfig = GatewayConfig(name: "Lab", kind: .direct, baseURL: "http://10.0.0.9:8877")
    let directRuntime = GatewayRuntime(config: directConfig, store: sshStore, tunnel: nil)
    #expect(directRuntime.reachableEndpointURL(for: status) == "http://10.0.0.9:8081/v1")

    let lanStatus = ModelFixtures.profileStatus(
        profile: "lan", host: "10.0.0.9", port: "8082", baseURL: "http://10.0.0.9:8082/v1"
    )
    #expect(directRuntime.reachableEndpointURL(for: lanStatus) == "http://10.0.0.9:8082/v1")
}
