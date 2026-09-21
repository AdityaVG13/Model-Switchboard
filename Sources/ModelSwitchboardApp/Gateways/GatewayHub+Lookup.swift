import Foundation
import Observation
import OSLog
import ModelSwitchboardCore

extension GatewayHub {
    var gatewayConfigs: [GatewayConfig] { remoteRuntimes.map(\.config) }
    var hasRemoteGateways: Bool { !remoteRuntimes.isEmpty }
    var enabledRemoteRuntimes: [GatewayRuntime] { remoteRuntimes.filter(\.config.enabled) }

    func runtime(id: String) -> GatewayRuntime? {
        remoteRuntimes.first(where: { $0.id == id })
    }

    func runtimeIndex(id: String) -> Int? {
        remoteRuntimes.firstIndex(where: { $0.id == id })
    }
}
