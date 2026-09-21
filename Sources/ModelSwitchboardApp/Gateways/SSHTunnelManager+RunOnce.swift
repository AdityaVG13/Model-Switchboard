import Foundation

extension SSHTunnelManager {
    /// Runs one ssh process to termination. Returns the user-facing failure text.
    func runTunnelOnce() async -> String {
        await reallocateLocalPortIfTaken()
        stderrTail = []
        let process = makeTunnelProcess()
        let terminated = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            terminated.continuation.yield()
            terminated.continuation.finish()
        }
        attachStderr(process)
        do {
            try process.run()
        } catch {
            return "Could not run ssh: \(error.localizedDescription)"
        }
        self.process = process

        let established = await waitUntilEstablished(process: process)
        if established {
            consecutiveFailures = 0
            let establishedAt = Date()
            await transition(to: .established)
            await restoreForwardsAfterReconnect()
            await awaitTermination(terminated.stream)
            noteUnstableUptime(establishedAt: establishedAt)
        } else {
            terminateProcess()
            await awaitTermination(terminated.stream)
        }
        finishTunnelProcess()
        return await failureAfterTunnelExit()
    }
}
