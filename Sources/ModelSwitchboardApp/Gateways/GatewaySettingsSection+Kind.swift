import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    /// Switching the connection kind rebuilds the payload from scratch - the
    /// other kind's fields cannot (and must not) carry over, so a gateway can
    /// never be saved with dead SSH/URL fields from a previous kind.
    func switchKind(_ config: inout GatewayConfig, to kind: GatewayKind) {
        guard config.kind != kind else { return }
        config = rebound(config, to: kind)
    }

    func rebound(_ config: GatewayConfig, to kind: GatewayKind) -> GatewayConfig {
        switch kind {
        case .ssh:
            return .ssh(
                id: config.id,
                name: config.name,
                sshUser: NSUserName(),
                sshHost: "",
                remotePort: config.remotePort,
                enabled: config.enabled
            )
        case .direct:
            return .direct(
                id: config.id,
                name: config.name,
                baseURL: "",
                remotePort: config.remotePort,
                enabled: config.enabled
            )
        }
    }
}
