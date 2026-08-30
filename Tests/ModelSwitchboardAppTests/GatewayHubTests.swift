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

        let config = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
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
        let config = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
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
        var first = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
        let second = GatewayConfig.direct(name: "Attic", baseURL: "http://10.0.0.7:8877")
        hub.upsertGateway(first, token: "")
        hub.upsertGateway(second, token: "")
        defer {
            hub.removeGateway(id: first.id)
            hub.removeGateway(id: second.id)
        }

        let untouched = try #require(hub.remoteRuntimes.first { $0.id == second.id })

        first = GatewayConfig.direct(id: first.id, name: first.name, baseURL: "http://10.0.0.10:8877")
        hub.upsertGateway(first, token: "")

        let rebuilt = try #require(hub.remoteRuntimes.first { $0.id == first.id })
        #expect(rebuilt.store.controllerBaseURL == "http://10.0.0.10:8877")
        // Unchanged gateways keep their runtime (and its running store) intact.
        #expect(hub.remoteRuntimes.first { $0.id == second.id } === untouched)
    }
}

@MainActor
@Test func tokenOnlyEditUpdatesLiveStoreWithoutRebuild() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
        hub.upsertGateway(config, token: "old-token-0123456789ab")
        defer { hub.removeGateway(id: config.id) }

        let runtime = try #require(hub.remoteRuntimes.first)
        #expect(runtime.store.controllerAuthToken == "old-token-0123456789ab")

        hub.upsertGateway(config, token: "new-token-0123456789ab")

        #expect(hub.remoteRuntimes.first === runtime)
        #expect(runtime.store.controllerAuthToken == "new-token-0123456789ab")
        #expect(hub.authToken(forGateway: config.id) == "new-token-0123456789ab")
    }
}

@MainActor
@Test func aggregatesSumAcrossGateways() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig.direct(name: "Spark", baseURL: "http://10.0.0.9:8877")
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
        let config = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark.invalid")
        hub.upsertGateway(config, token: "")
        defer { hub.removeGateway(id: config.id) }

        let runtime = try #require(hub.remoteRuntimes.first)
        let tunnelID = try #require(runtime.tunnel?.instanceID)
        hub.tunnelStateChanged(gatewayID: config.id, tunnelID: tunnelID, state: .failed("SSH auth failed."))

        #expect(runtime.tunnelState == .failed("SSH auth failed."))
        #expect(runtime.store.refreshState == .blocked(message: "SSH auth failed."))
        #expect(hub.localStore.lastError == nil)
    }
}

@MainActor
@Test func tunnelEstablishedStartsRemoteRefresh() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark.invalid")
        hub.upsertGateway(config, token: "")
        defer { hub.removeGateway(id: config.id) }

        let runtime = try #require(hub.remoteRuntimes.first)
        #expect(runtime.store.refreshTask == nil)

        let tunnelID = try #require(runtime.tunnel?.instanceID)
        hub.tunnelStateChanged(gatewayID: config.id, tunnelID: tunnelID, state: .established)
        #expect(runtime.store.refreshTask != nil)
    }
}

@MainActor
@Test func staleTunnelCallbackIsIgnoredAfterReplacement() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark.invalid")
        hub.upsertGateway(config, token: "")
        defer { hub.removeGateway(id: config.id) }

        let runtime = try #require(hub.remoteRuntimes.first)
        let liveID = try #require(runtime.tunnel?.instanceID)
        hub.tunnelStateChanged(gatewayID: config.id, tunnelID: liveID, state: .established)
        #expect(runtime.tunnelState == .established)

        // A replaced tunnel's terminal .idle must not wipe the live runtime.
        hub.tunnelStateChanged(gatewayID: config.id, tunnelID: UUID(), state: .idle)
        #expect(runtime.tunnelState == .established)
        #expect(runtime.store.refreshTask != nil)
    }
}

@MainActor
@Test func reachableEndpointURLHonorsForwardsAndDirectHosts() {
    let sshConfig = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark")
    let sshStore = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9999",
        features: .base,
        gateway: GatewayContext(config: sshConfig),
        autoStartRefresh: false
    )
    let sshRuntime = GatewayRuntime(config: sshConfig, store: sshStore, tunnel: nil)
    let loopbackStatus = ModelFixtures.profileStatus(
        profile: "qwen", port: "8081", baseURL: "http://127.0.0.1:8081/v1"
    )

    #expect(sshRuntime.reachableEndpointURL(for: loopbackStatus) == nil)
    sshRuntime.forwardedPorts = [8081: 8081]
    #expect(sshRuntime.reachableEndpointURL(for: loopbackStatus) == "http://127.0.0.1:8081/v1")
    // Remapped local port when the remote number is occupied on this Mac.
    sshRuntime.forwardedPorts = [8081: 49152]
    #expect(sshRuntime.reachableEndpointURL(for: loopbackStatus) == "http://127.0.0.1:49152/v1")

    let directConfig = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
    let directRuntime = GatewayRuntime(config: directConfig, store: sshStore, tunnel: nil)
    // Default loopback bind is not reachable via the controller host.
    #expect(directRuntime.reachableEndpointURL(for: loopbackStatus) == nil)

    // Non-loopback bind (HOST=0.0.0.0) with loopback-advertised base_url: rewrite.
    let allInterfacesStatus = ModelFixtures.profileStatus(
        profile: "qwen",
        host: "0.0.0.0",
        port: "8081",
        baseURL: "http://127.0.0.1:8081/v1"
    )
    #expect(directRuntime.reachableEndpointURL(for: allInterfacesStatus) == "http://10.0.0.9:8081/v1")

    let lanStatus = ModelFixtures.profileStatus(
        profile: "lan", host: "10.0.0.9", port: "8082", baseURL: "http://10.0.0.9:8082/v1"
    )
    #expect(directRuntime.reachableEndpointURL(for: lanStatus) == "http://10.0.0.9:8082/v1")
}

@MainActor
@Test func renameGatewayUpdatesLabelWithoutReplacingRuntime() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig.direct(name: "Spark", baseURL: "http://10.0.0.9:8877")
        hub.upsertGateway(config, token: "tok-0123456789abcdef")
        defer { hub.removeGateway(id: config.id) }

        let before = try #require(hub.remoteRuntimes.first)
        #expect(before.name == "Spark")

        #expect(hub.renameGateway(id: config.id, to: "Lab Box"))
        let after = try #require(hub.remoteRuntimes.first)
        #expect(after.name == "Lab Box")
        // Same runtime instance - connection was not torn down for a label change.
        #expect(after === before)
        #expect(after.store.controllerBaseURL == "http://10.0.0.9:8877")
        #expect(GatewayConfigStore.load(from: defaults).first?.name == "Lab Box")
    }
}


@MainActor
@Test func discardLiveStatusForForceUpdateClearsBoard() throws {
    try withTestDefaults { defaults, service in
        let hub = makeHub(defaults: defaults, keychainService: service)
        let config = GatewayConfig.direct(name: "Spark", baseURL: "http://10.0.0.9:8877")
        hub.upsertGateway(config, token: "")
        defer { hub.removeGateway(id: config.id) }

        let runtime = try #require(hub.remoteRuntimes.first)
        runtime.store.statuses = [
            ModelFixtures.profileStatus(profile: "stale", port: "8000", running: true, ready: true)
        ]
        runtime.store.lastUpdated = Date()
        runtime.store.refreshState = .failed(message: "stale")

        runtime.store.discardLiveStatusForForceUpdate()

        #expect(runtime.store.statuses.isEmpty)
        #expect(runtime.store.lastUpdated == nil)
        #expect(runtime.store.refreshState == .idle)
        #expect(runtime.store.lastError == nil)
    }
}

@MainActor
@Test func forceUpdateRedeploysWhenSSHHostPresent() async throws {
    await withTestDefaultsAsync { defaults, service in
        var deployCalls = 0
        var sawTailscale: Bool?
        let hub = GatewayHub(
            localStore: makeLocalStore(),
            defaults: defaults,
            remoteStoreFactory: { config, baseURL, token in
                SwitchboardStore(
                    controllerBaseURL: baseURL,
                    controllerAuthToken: token,
                    features: .base,
                    gateway: GatewayContext(config: config),
                    autoStartRefresh: false,
                    controllerClientFactory: { _, _ in throw TestBoom() }
                )
            },
            tokenStorageFactory: { id in
                KeychainTokenStorage(service: service, accessGroup: nil, account: "gateway-\(id)")
            },
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/true"),
            deployAgent: { ssh, useTailscale, _ in
                deployCalls += 1
                sawTailscale = useTailscale
                #expect(ssh.sshHost == "spark.local")
                return RemoteAgentDeployer.Result(
                    pairingLink: nil,
                    authToken: "new-token-0123456789ab",
                    log: "ok"
                )
            }
        )
        let config = GatewayConfig.ssh(
            name: "Spark",
            sshUser: "ubuntu",
            sshHost: "spark.local",
            remotePort: 8877
        )
        hub.upsertGateway(config, token: "old-token-0123456789ab")
        defer { hub.removeGateway(id: config.id) }

        await hub.forceUpdateGateway(id: config.id)

        #expect(deployCalls == 1)
        #expect(sawTailscale == false)
        #expect(hub.authToken(forGateway: config.id) == "new-token-0123456789ab")
    }
}

@MainActor
@Test func forceUpdateUsesDerivedHostForDirectGateway() async throws {
    try await withTestDefaultsAsync { defaults, service in
        var deployHosts: [String] = []
        var sawTailscale: Bool?
        let hub = GatewayHub(
            localStore: makeLocalStore(),
            defaults: defaults,
            remoteStoreFactory: { config, baseURL, token in
                SwitchboardStore(
                    controllerBaseURL: baseURL,
                    controllerAuthToken: token,
                    features: .base,
                    gateway: GatewayContext(config: config),
                    autoStartRefresh: false,
                    controllerClientFactory: { _, _ in throw TestBoom() }
                )
            },
            tokenStorageFactory: { id in
                KeychainTokenStorage(service: service, accessGroup: nil, account: "gateway-\(id)")
            },
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/true"),
            deployAgent: { ssh, useTailscale, _ in
                deployHosts.append(ssh.sshHost)
                sawTailscale = useTailscale
                return RemoteAgentDeployer.Result(pairingLink: nil, authToken: nil, log: "ok")
            }
        )
        // A direct gateway carries no ssh fields. Force-update derives an SSH
        // target from the URL hostname without minting a fake SSH gateway.
        let config = GatewayConfig.direct(
            name: "Spark",
            baseURL: "http://dgx-spark.tail123.ts.net:8877"
        )
        let deploy = GatewayHub.agentDeployTarget(for: config)
        #expect(deploy?.sshHost == "dgx-spark.tail123.ts.net")
        hub.upsertGateway(config, token: "tok")
        defer { hub.removeGateway(id: config.id) }

        await hub.forceUpdateGateway(id: config.id)

        #expect(deployHosts == ["dgx-spark.tail123.ts.net"])
        #expect(sawTailscale == true)
    }
}


@MainActor
@Test func forceUpdatePassesProfilesDirectoryToDeploy() async throws {
    await withTestDefaultsAsync { defaults, service in
        var sawProfilesDir: String?
        let hub = GatewayHub(
            localStore: makeLocalStore(),
            defaults: defaults,
            remoteStoreFactory: { config, baseURL, token in
                let store = SwitchboardStore(
                    controllerBaseURL: baseURL,
                    controllerAuthToken: token,
                    features: .base,
                    gateway: GatewayContext(config: config),
                    autoStartRefresh: false,
                    controllerClientFactory: { _, _ in throw TestBoom() }
                )
                store.profilesDirectory = "/custom/model-profiles"
                return store
            },
            tokenStorageFactory: { id in
                KeychainTokenStorage(service: service, accessGroup: nil, account: "gateway-\(id)")
            },
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/true"),
            deployAgent: { _, _, profilesDirectory in
                sawProfilesDir = profilesDirectory
                return RemoteAgentDeployer.Result(pairingLink: nil, authToken: nil, log: "ok")
            }
        )
        let config = GatewayConfig.ssh(
            name: "Spark",
            sshUser: "ubuntu",
            sshHost: "spark.local",
            remotePort: 8877
        )
        hub.upsertGateway(config, token: "tok")
        defer { hub.removeGateway(id: config.id) }

        await hub.forceUpdateGateway(id: config.id)

        #expect(sawProfilesDir == "/custom/model-profiles")
    }
}

@Test func remoteGatewayHTTPTimeoutsLeaveRoomForDiscovery() {
    // Cold /api/status on a busy vLLM host previously took ~15s while the Mac
    // client aborted at 5s request / 15s resource - permanent DIRECT · ERROR.
    #expect(GatewayHub.RemoteHTTPTimeouts.request >= 30)
    #expect(GatewayHub.RemoteHTTPTimeouts.resource >= GatewayHub.RemoteHTTPTimeouts.request)
}

@MainActor
private func withTestDefaultsAsync(
    _ body: @MainActor (UserDefaults, String) async throws -> Void
) async rethrows {
    let suiteName = "io.modelswitchboard.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = "io.modelswitchboard.tests.\(UUID().uuidString)"
    try await body(defaults, service)
}
