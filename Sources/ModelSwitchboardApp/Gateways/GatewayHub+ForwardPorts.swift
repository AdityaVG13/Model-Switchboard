import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func isLiveForwardTunnel(_ runtime: GatewayRuntime, tunnelID: UUID) -> Bool {
        runtime.tunnel?.instanceID == tunnelID && runtime.tunnelState.isEstablished
    }

    func applyForwardedPorts(_ forwarded: [Int: Int], to runtime: GatewayRuntime) {
        if runtime.forwardedPorts != forwarded {
            runtime.forwardedPorts = forwarded
        }
    }

    func runningForwardPorts(in runtime: GatewayRuntime) -> Set<Int> {
        Set(
            runtime.store.statuses.boardVisible
                .filter { $0.running || $0.ready }
                .compactMap { Int($0.port) }
        )
    }
}
