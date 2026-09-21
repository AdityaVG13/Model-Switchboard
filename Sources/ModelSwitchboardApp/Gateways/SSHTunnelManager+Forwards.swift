import Foundation
import ModelSwitchboardCore

extension SSHTunnelManager {
    /// Aligns per-model forwards with the given remote ports. Prefers mapping
    /// remote N → local N when free; otherwise allocates an ephemeral local
    /// port. Returns the remote→local map that is actually forwarded now.
    @discardableResult
    func syncForwards(remotePorts: Set<Int>) async -> [Int: Int] {
        guard state.isEstablished else { return activeForwards }
        await cancelStaleForwards(Set(activeForwards.keys).subtracting(remotePorts))
        await addMissingForwards(remotePorts.subtracting(activeForwards.keys))
        return activeForwards
    }

    func cancelStaleForwards(_ stale: Set<Int>) async {
        for remotePort in stale {
            guard let localPort = activeForwards[remotePort] else { continue }
            _ = await runControlCommand(["-O", "cancel", "-L", Self.forwardSpec(local: localPort, remote: remotePort)])
            activeForwards.removeValue(forKey: remotePort)
        }
    }

    func addMissingForwards(_ missing: Set<Int>) async {
        for remotePort in missing {
            guard let localPort = allocateForwardLocalPort(preferring: remotePort) else { continue }
            if await runControlCommand(["-O", "forward", "-L", Self.forwardSpec(local: localPort, remote: remotePort)]) {
                activeForwards[remotePort] = localPort
            }
        }
    }
}
