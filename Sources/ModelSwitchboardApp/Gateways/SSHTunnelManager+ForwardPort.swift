import Darwin
import Foundation
import ModelSwitchboardCore

extension SSHTunnelManager {
    /// Local ports already claimed by this tunnel (agent forward + model forwards).
    var reservedLocalPorts: Set<Int> {
        Set(activeForwards.values).union([Int(localPort)])
    }

    func isLocalPortAvailableForForward(_ port: Int) -> Bool {
        guard TCPPort.isValid(port) else { return false }
        guard !reservedLocalPorts.contains(port) else { return false }
        return Self.isLoopbackPortFree(UInt16(port))
    }

    /// Prefer the remote port number locally when free; otherwise ephemeral.
    func allocateForwardLocalPort(preferring remotePort: Int) -> Int? {
        if isLocalPortAvailableForForward(remotePort) {
            return remotePort
        }
        for _ in 0..<5 {
            let allocated = Self.allocateLoopbackPort()
            guard allocated != 0 else { return nil }
            let asInt = Int(allocated)
            if !reservedLocalPorts.contains(asInt) {
                return asInt
            }
        }
        return nil
    }
}
