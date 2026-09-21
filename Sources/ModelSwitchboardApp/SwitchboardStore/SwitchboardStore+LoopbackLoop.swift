import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func startLoopbackEndpointProbe() {
        // Remote profiles report URLs that are loopback on the *remote* host;
        // probing 127.0.0.1 here would mark healthy remote servers dead.
        guard gateway.isLocal else { return }
        loopbackEndpointProbeTask?.cancel()
        loopbackEndpointProbeSession = loopbackEndpointProbeSession ?? Self.makeLoopbackEndpointProbeSession()
        loopbackEndpointProbeTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoopbackEndpointProbeLoop()
        }
    }

    func runLoopbackEndpointProbeLoop() async {
        await probeLoopbackEndpointsIfNeeded()
        while !Task.isCancelled {
            guard await sleepUntilNextLoopbackProbe() else { return }
            if Task.isCancelled { break }
            await probeLoopbackEndpointsIfNeeded()
        }
    }

    func sleepUntilNextLoopbackProbe() async -> Bool {
        do {
            try await Task.sleep(for: .seconds(nextLoopbackEndpointProbeInterval()))
            return true
        } catch {
            if isBenignCancellation(error) { return false }
            Self.logger.error("Loopback endpoint probe sleep failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
