import Foundation

extension SSHTunnelManager {
    func awaitTermination(_ stream: AsyncStream<Void>) async {
        for await _ in stream { break }
    }

    func noteUnstableUptime(establishedAt: Date) {
        if Date().timeIntervalSince(establishedAt) < Self.stableUptimeSeconds {
            consecutiveFailures += 1
        }
    }

    func finishTunnelProcess() {
        process = nil
        activeForwards = [:]
    }

    func failureAfterTunnelExit() async -> String {
        let failure = Self.classifyFailure(stderrLines: stderrTail)
        if Self.looksLikeLocalPortInUse(stderrLines: stderrTail) {
            await reallocateLocalPortIfTaken(force: true)
        }
        return failure
    }
}
