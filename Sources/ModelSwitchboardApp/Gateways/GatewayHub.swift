import Foundation
import Observation
import OSLog
import ModelSwitchboardCore

/// Owns the local store plus one runtime per configured remote gateway,
/// and the cross-gateway aggregates the menu bar shows.
@MainActor
@Observable
final class GatewayHub {
    typealias RemoteStoreFactory = @MainActor (GatewayConfig, String, String) -> SwitchboardStore

    static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "gateway-hub")
    static let forwardSyncIntervalSeconds: TimeInterval = 5

    let localStore: SwitchboardStore
    var remoteRuntimes: [GatewayRuntime] = []

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let remoteStoreFactory: RemoteStoreFactory
    @ObservationIgnored let tokenStorageFactory: (String) -> KeychainTokenStorage
    @ObservationIgnored let sshExecutableURL: URL
    @ObservationIgnored let deployAgent: @MainActor (
        GatewayConfig.Connection.SSH, Bool, String?
    ) async throws -> RemoteAgentDeployer.Result
    /// Coalesce spam-clicks on the dashboard refresh control.
    @ObservationIgnored var lastManualRefreshAt: Date?

    init(
        localStore: SwitchboardStore,
        defaults: UserDefaults = .standard,
        remoteStoreFactory: RemoteStoreFactory? = nil,
        tokenStorageFactory: @escaping (String) -> KeychainTokenStorage = { KeychainTokenStorage.forGateway(id: $0) },
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        deployAgent: (@MainActor (
            GatewayConfig.Connection.SSH, Bool, String?
        ) async throws -> RemoteAgentDeployer.Result)? = nil
    ) {
        self.localStore = localStore
        self.defaults = defaults
        if let remoteStoreFactory {
            self.remoteStoreFactory = remoteStoreFactory
        } else {
            self.remoteStoreFactory = Self.defaultRemoteStoreFactory()
        }
        self.tokenStorageFactory = tokenStorageFactory
        self.sshExecutableURL = sshExecutableURL
        self.deployAgent = deployAgent ?? Self.defaultDeployAgent()
        applyConfigs(GatewayConfigStore.load(from: defaults))
    }
}
