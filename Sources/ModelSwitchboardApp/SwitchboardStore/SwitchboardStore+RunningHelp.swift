import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func runningStatusesHelp() -> String {
        let running = sortedStatuses.filter(\.running)
        guard !running.isEmpty else {
            return gateway.isLocal
                ? "No local models running"
                : "No models running on \(gateway.name)"
        }
        let prefix = gateway.isLocal ? "Running" : "\(gateway.name)"
        return "\(prefix): " + running.map(\.displayName).joined(separator: ", ")
    }
}
