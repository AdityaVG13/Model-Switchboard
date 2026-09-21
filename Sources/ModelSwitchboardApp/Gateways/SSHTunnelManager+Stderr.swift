import Foundation

extension SSHTunnelManager {
    func terminateProcess() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
    }

    func appendStderr(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            stderrTail.append(String(line))
        }
        if stderrTail.count > 20 {
            stderrTail.removeFirst(stderrTail.count - 20)
        }
    }

    func transition(to newState: State) async {
        guard state != newState else { return }
        state = newState
        Self.logger.info("tunnel \(self.gatewayID, privacy: .public): \(String(describing: newState), privacy: .public)")
        await onStateChange(instanceID, newState)
    }
}
