import Foundation

extension SSHTunnelManager {
    func supervise() async {
        while desiredActive, !Task.isCancelled {
            await transition(to: .connecting)
            let outcome = await runTunnelOnce()
            guard desiredActive, !Task.isCancelled else { break }
            await transition(to: .failed(outcome))
            consecutiveFailures += 1
            let backoff = Self.backoffDelay(afterFailures: consecutiveFailures)
            try? await Task.sleep(for: .seconds(backoff))
        }
    }
}
