import Foundation

extension SSHTunnelManager {
    /// The `-L` listener only opens after authentication succeeds. Require both
    /// a local connect *and* a live ControlMaster - bare TCP can succeed against
    /// a port squatter while ssh is still authenticating.
    func waitUntilEstablished(process: Process) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.establishTimeoutSeconds)
        while Date() < deadline, process.isRunning, desiredActive {
            let connected = await Self.offPool { Self.canConnectLoopback(port: self.localPort) }
            if connected, await runControlCommand(["-O", "check"]) {
                return true
            }
            try? await Task.sleep(for: .seconds(Self.establishPollSeconds))
        }
        return false
    }

    static func offPool<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: body())
            }
        }
    }
}
