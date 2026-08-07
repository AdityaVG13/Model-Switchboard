import Foundation
import Observation
import OSLog
import ModelSwitchboardCore

/// One gateway's live state: its store, and for SSH gateways the tunnel.
@MainActor
@Observable
final class GatewayRuntime: Identifiable {
    nonisolated let id: String
    private(set) var config: GatewayConfig
    let store: SwitchboardStore
    let tunnel: SSHTunnelManager?
    var tunnelState: SSHTunnelManager.State = .idle
    /// Remote model port → local loopback port currently forwarded over SSH.
    var forwardedPorts: [Int: Int] = [:]
    @ObservationIgnored var forwardSyncTask: Task<Void, Never>?

    init(config: GatewayConfig, store: SwitchboardStore, tunnel: SSHTunnelManager?) {
        self.id = config.id
        self.config = config
        self.store = store
        self.tunnel = tunnel
    }

    var name: String { config.name }

    /// Update stored config without rebuilding the store/tunnel (label renames).
    fileprivate func applyConfigPreservingConnection(_ config: GatewayConfig) {
        self.config = config
    }

    /// A URL for this profile that is valid from this Mac, or nil when the
    /// endpoint is only reachable on the remote host.
    func reachableEndpointURL(for status: ModelProfileStatus) -> String? {
        switch config.kind {
        case .ssh:
            // Forwards may remap remote N → a different local port when N is
            // already taken (second gateway, local server, etc.).
            guard let remotePort = Int(status.port),
                  let localPort = forwardedPorts[remotePort],
                  var components = URLComponents(string: status.baseURL)
            else { return nil }
            components.host = "127.0.0.1"
            components.port = localPort
            return components.url?.absoluteString
        case .direct:
            if !status.usesLoopbackEndpoint {
                return status.baseURL
            }
            // Agent status always advertises loopback `base_url` unless BASE_URL
            // is set. Rewriting that to the controller's LAN/tailnet host only
            // works when the model process itself is bound beyond loopback
            // (HOST=0.0.0.0 / a real interface). A default 127.0.0.1 bind stays
            // remote-only — Copy Endpoint would otherwise hand out a dead URL.
            guard !LoopbackHost.isLoopback(status.host) else { return nil }
            guard
                let controllerHost = URL(string: config.baseURL)?.host,
                !LoopbackHost.isLoopback(controllerHost),
                var components = URLComponents(string: status.baseURL)
            else { return nil }
            components.host = controllerHost
            return components.url?.absoluteString
        }
    }
}

/// Owns the local store plus one runtime per configured remote gateway,
/// and the cross-gateway aggregates the menu bar shows.
@MainActor
@Observable
final class GatewayHub {
    typealias RemoteStoreFactory = @MainActor (GatewayConfig, String, String) -> SwitchboardStore

    private static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "gateway-hub")
    private static let forwardSyncIntervalSeconds: TimeInterval = 5

    let localStore: SwitchboardStore
    private(set) var remoteRuntimes: [GatewayRuntime] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let remoteStoreFactory: RemoteStoreFactory
    @ObservationIgnored private let tokenStorageFactory: (String) -> KeychainTokenStorage
    @ObservationIgnored private let sshExecutableURL: URL
    /// Coalesce spam-clicks on the dashboard refresh control.
    @ObservationIgnored private var lastManualRefreshAt: Date?

    init(
        localStore: SwitchboardStore,
        defaults: UserDefaults = .standard,
        remoteStoreFactory: RemoteStoreFactory? = nil,
        tokenStorageFactory: @escaping (String) -> KeychainTokenStorage = { KeychainTokenStorage.forGateway(id: $0) },
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh")
    ) {
        self.localStore = localStore
        self.defaults = defaults
        self.remoteStoreFactory = remoteStoreFactory ?? Self.makeRemoteStore
        self.tokenStorageFactory = tokenStorageFactory
        self.sshExecutableURL = sshExecutableURL
        applyConfigs(GatewayConfigStore.load(from: defaults))
    }

    // MARK: - Configuration lifecycle

    var gatewayConfigs: [GatewayConfig] { remoteRuntimes.map(\.config) }
    var hasRemoteGateways: Bool { !remoteRuntimes.isEmpty }
    var enabledRemoteRuntimes: [GatewayRuntime] { remoteRuntimes.filter(\.config.enabled) }

    func upsertGateway(_ config: GatewayConfig, token: String) {
        let storage = tokenStorageFactory(config.id)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty field means "leave the keychain token alone" — never wipe a
        // saved token just because SecureField was blank on Save.
        if !trimmed.isEmpty {
            storage.save(trimmed)
        }
        var configs = GatewayConfigStore.load(from: defaults)
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        GatewayConfigStore.save(configs, to: defaults)
        applyConfigs(configs)
    }

    func removeGateway(id: String) {
        tokenStorageFactory(id).delete()
        let configs = GatewayConfigStore.load(from: defaults).filter { $0.id != id }
        GatewayConfigStore.save(configs, to: defaults)
        applyConfigs(configs)
    }

    func authToken(forGateway id: String) -> String {
        tokenStorageFactory(id).load() ?? ""
    }

    /// Rename a gateway without restarting its tunnel or status store.
    @discardableResult
    func renameGateway(id: String, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var configs = GatewayConfigStore.load(from: defaults)
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return false }
        guard configs[index].name != trimmed else { return true }
        configs[index].name = trimmed
        GatewayConfigStore.save(configs, to: defaults)
        applyConfigs(configs)
        return true
    }

    /// Connection identity: everything except the operator-facing display name.
    private static func sameConnection(_ lhs: GatewayConfig, _ rhs: GatewayConfig) -> Bool {
        var a = lhs
        var b = rhs
        a.name = ""
        b.name = ""
        return a == b
    }

    func applyConfigs(_ configs: [GatewayConfig]) {
        var kept: [String: GatewayRuntime] = [:]
        for runtime in remoteRuntimes {
            if let config = configs.first(where: { $0.id == runtime.id }) {
                if config == runtime.config {
                    // Config Equatable ignores the Keychain token. Sync credentials
                    // onto the kept store so token-only edits take effect without a
                    // rebuild (and without waiting for app restart).
                    syncAuthToken(onto: runtime)
                    kept[runtime.id] = runtime
                } else if Self.sameConnection(config, runtime.config) {
                    // Display name (or other non-connection fields) only — keep tunnel/store.
                    runtime.applyConfigPreservingConnection(config)
                    syncAuthToken(onto: runtime)
                    kept[runtime.id] = runtime
                } else {
                    teardown(runtime)
                }
            } else {
                teardown(runtime)
            }
        }
        remoteRuntimes = configs.compactMap { config in
            if let existing = kept[config.id] { return existing }
            guard config.enabled else { return nil }
            return makeRuntime(config: config)
        }
    }

    private func syncAuthToken(onto runtime: GatewayRuntime) {
        let token = tokenStorageFactory(runtime.id).load() ?? ""
        guard runtime.store.controllerAuthToken != token else { return }
        runtime.store.controllerAuthToken = token
        Task { await runtime.store.refresh() }
    }

    private func makeRuntime(config: GatewayConfig) -> GatewayRuntime {
        let token = tokenStorageFactory(config.id).load() ?? ""
        switch config.kind {
        case .direct:
            let store = remoteStoreFactory(config, config.baseURL, token)
            return GatewayRuntime(config: config, store: store, tunnel: nil)
        case .ssh:
            let hubReference = WeakHub(self)
            let tunnel = SSHTunnelManager(
                gatewayID: config.id,
                configuration: .init(config: config),
                executableURL: sshExecutableURL,
                onStateChange: { tunnelID, state in
                    await hubReference.value?.tunnelStateChanged(
                        gatewayID: config.id,
                        tunnelID: tunnelID,
                        state: state
                    )
                },
                onLocalPortChange: { tunnelID, port in
                    await hubReference.value?.tunnelLocalPortChanged(
                        gatewayID: config.id,
                        tunnelID: tunnelID,
                        localPort: port
                    )
                }
            )
            let store = remoteStoreFactory(config, tunnel.localBaseURL, token)
            let runtime = GatewayRuntime(config: config, store: store, tunnel: tunnel)
            Task { await tunnel.start() }
            return runtime
        }
    }

    private func teardown(_ runtime: GatewayRuntime) {
        runtime.store.stopAutoRefresh()
        runtime.forwardSyncTask?.cancel()
        runtime.forwardSyncTask = nil
        if let tunnel = runtime.tunnel {
            // Instance-unique control sockets mean a replacement tunnel for the
            // same gateway id can start immediately without racing this stop.
            // State callbacks are filtered by tunnel.instanceID so the old
            // stop()'s terminal .idle cannot poison the replacement.
            Task { await tunnel.stop() }
        }
    }

    // MARK: - Tunnel state

    func tunnelStateChanged(
        gatewayID: String,
        tunnelID: UUID,
        state: SSHTunnelManager.State
    ) {
        guard let runtime = remoteRuntimes.first(where: { $0.id == gatewayID }) else { return }
        // Ignore late events from a tunnel that was replaced for this gateway.
        if let current = runtime.tunnel, current.instanceID != tunnelID {
            return
        }
        runtime.tunnelState = state
        switch state {
        case .established:
            // (Re)start the refresh loop now that requests can get through, and
            // keep model-endpoint forwards aligned with running profiles.
            runtime.store.startAutoRefresh()
            startForwardSync(for: runtime)
        case .failed(let message):
            runtime.store.applyBootstrapDiagnostic(message)
            runtime.store.stopAutoRefresh()
            runtime.forwardSyncTask?.cancel()
            runtime.forwardSyncTask = nil
            runtime.forwardedPorts = [:]
        case .connecting, .idle:
            // Don't keep polling a dead/not-yet-ready forward.
            if case .idle = state {
                runtime.store.stopAutoRefresh()
            }
            runtime.forwardSyncTask?.cancel()
            runtime.forwardSyncTask = nil
            runtime.forwardedPorts = [:]
        }
    }

    func tunnelLocalPortChanged(gatewayID: String, tunnelID: UUID, localPort: UInt16) {
        guard let runtime = remoteRuntimes.first(where: { $0.id == gatewayID }) else { return }
        guard let current = runtime.tunnel, current.instanceID == tunnelID else { return }
        let baseURL = "http://127.0.0.1:\(localPort)"
        guard runtime.store.controllerBaseURL != baseURL else { return }
        runtime.store.controllerBaseURL = baseURL
        Task { await runtime.store.refresh() }
    }

    private func startForwardSync(for runtime: GatewayRuntime) {
        runtime.forwardSyncTask?.cancel()
        guard let tunnel = runtime.tunnel else { return }
        let tunnelID = tunnel.instanceID
        runtime.forwardSyncTask = Task { [weak runtime] in
            while !Task.isCancelled {
                guard let runtime else { return }
                guard runtime.tunnel?.instanceID == tunnelID,
                      runtime.tunnelState == .established
                else { return }
                let runningPorts = Set(
                    runtime.store.statuses
                        .filter { $0.running || $0.ready }
                        .compactMap { Int($0.port) }
                )
                let forwarded = await tunnel.syncForwards(remotePorts: runningPorts)
                // A cancelled / replaced tunnel must not repopulate forwardedPorts
                // with stale specs (Copy Endpoint would lie).
                guard !Task.isCancelled else { return }
                guard runtime.tunnel?.instanceID == tunnelID,
                      runtime.tunnelState == .established
                else { return }
                if runtime.forwardedPorts != forwarded {
                    runtime.forwardedPorts = forwarded
                }
                try? await Task.sleep(for: .seconds(Self.forwardSyncIntervalSeconds))
            }
        }
    }

    // MARK: - Aggregates

    var allStores: [SwitchboardStore] { [localStore] + enabledRemoteRuntimes.map(\.store) }

    var totalProfiles: Int {
        allStores.reduce(0) { $0 + $1.summary.totalProfiles }
    }

    var displayedReadyProfiles: Int {
        allStores.reduce(0) { $0 + $1.displayedReadyProfiles }
    }

    var displayedRunningProfiles: Int {
        allStores.reduce(0) { $0 + $1.displayedRunningProfiles }
    }

    var menuBarHelp: String {
        guard hasRemoteGateways else { return localStore.menuBarHelp }
        let parts = [
            "This Mac: \(localStore.displayedReadyProfiles)/\(localStore.summary.totalProfiles) ready"
        ] + enabledRemoteRuntimes.map { runtime in
            "\(runtime.name): \(runtime.store.displayedReadyProfiles)/\(runtime.store.summary.totalProfiles) ready"
        }
        return parts.joined(separator: " · ")
    }

    var isStopEverythingBusy: Bool {
        allStores.contains { $0.pendingGlobalActions.contains("stop-all") }
    }

    func stopEverything() async {
        // Unstructured MainActor-inheriting tasks: stores run their stop-alls
        // concurrently while each store mutation stays on the main actor.
        let tasks = allStores.map { store in
            Task { await store.stopAll() }
        }
        for task in tasks {
            await task.value
        }
    }

    func refreshAll() {
        let now = Date()
        // Manual refresh is already coalesced per-store via `isRefreshing`, but
        // the header used to swap controls on every press; still debounce the
        // kick so we do not stack remote status storms (~1s each).
        if let lastManualRefreshAt, now.timeIntervalSince(lastManualRefreshAt) < 0.75 {
            return
        }
        lastManualRefreshAt = now
        for store in allStores {
            Task { await store.refresh() }
        }
    }

    // MARK: - Default remote store construction

    @MainActor
    private static func makeRemoteStore(
        config: GatewayConfig, baseURL: String, token: String
    ) -> SwitchboardStore {
        // Short timeouts: a half-open tunnel must not hang the panel for 60s.
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 5
        sessionConfiguration.timeoutIntervalForResource = 15
        sessionConfiguration.waitsForConnectivity = false
        // Bypass system HTTP(S) proxies so tunnel loopback / Tailscale direct
        // agent traffic cannot be diverted off-box.
        sessionConfiguration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: sessionConfiguration)
        return SwitchboardStore(
            controllerBaseURL: baseURL,
            controllerAuthToken: token,
            // Inherit the app edition so Plus can benchmark remote models.
            features: .current,
            gateway: GatewayContext(config: config),
            autoStartRefresh: config.kind == .direct,
            controllerClientFactory: { baseURLString, authToken in
                try ControllerClient(baseURLString: baseURLString, authToken: authToken, session: session)
            }
        )
    }
}

/// Lets the tunnel's @Sendable callback reach the MainActor hub without a
/// retain cycle (hub → tunnel → callback → hub).
private final class WeakHub: @unchecked Sendable {
    private weak var hub: GatewayHub?

    init(_ hub: GatewayHub) {
        self.hub = hub
    }

    @MainActor
    var value: GatewayHub? { hub }
}
