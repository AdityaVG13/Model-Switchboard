import Foundation

extension SSHTunnelManager {
    func start() {
        guard !desiredActive else { return }
        if configuration.isUnsafeDestination {
            Task {
                await transition(to: .failed(
                    "SSH user/host cannot start with '-' (would be parsed as an ssh option)."
                ))
            }
            return
        }
        guard localPort != 0 else {
            Task {
                await transition(to: .failed("Could not allocate a local loopback port for the SSH tunnel."))
            }
            return
        }
        desiredActive = true
        consecutiveFailures = 0
        supervisorTask = Task { await supervise() }
    }

    func stop() async {
        desiredActive = false
        supervisorTask?.cancel()
        supervisorTask = nil
        terminateProcess()
        activeForwards = [:]
        try? FileManager.default.removeItem(atPath: controlSocketPath())
        await transition(to: .idle)
    }
}
