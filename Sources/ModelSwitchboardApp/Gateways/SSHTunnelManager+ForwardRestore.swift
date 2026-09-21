import Foundation
import ModelSwitchboardCore

extension SSHTunnelManager {
    func restoreForwardsAfterReconnect() async {
        let wanted = activeForwards
        activeForwards = [:]
        guard state.isEstablished, !wanted.isEmpty else { return }
        for (remotePort, preferredLocal) in wanted {
            let localPort: Int
            if isLocalPortAvailableForForward(preferredLocal) {
                localPort = preferredLocal
            } else if let allocated = allocateForwardLocalPort(preferring: remotePort) {
                localPort = allocated
            } else {
                continue
            }
            if await runControlCommand(["-O", "forward", "-L", Self.forwardSpec(local: localPort, remote: remotePort)]) {
                activeForwards[remotePort] = localPort
            }
        }
    }

    static func forwardSpec(local: Int, remote: Int) -> String {
        "127.0.0.1:\(local):127.0.0.1:\(remote)"
    }
}
