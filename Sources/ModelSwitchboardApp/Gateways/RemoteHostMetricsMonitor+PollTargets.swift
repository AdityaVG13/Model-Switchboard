import Foundation
import ModelSwitchboardCore

extension RemoteHostMetricsMonitor {
    func dropStaleHostEntries(activeIDs: Set<String>) {
        for id in entries.keys where !activeIDs.contains(id) {
            entries.removeValue(forKey: id)
        }
    }

    func pollTarget(for runtime: GatewayRuntime) -> RemoteHostMetricsPollTarget {
        let previous = entries[runtime.id] ?? Entry()
        if runtime.config.kind == .ssh, runtime.tunnelState != .established {
            return blockedSSHPollTarget(id: runtime.id, previous: previous, runtime: runtime)
        }
        return clientPollTarget(id: runtime.id, previous: previous, store: runtime.store)
    }

    func blockedSSHPollTarget(
        id: String,
        previous: Entry,
        runtime: GatewayRuntime
    ) -> RemoteHostMetricsPollTarget {
        RemoteHostMetricsPollTarget(
            id: id,
            previous: previous,
            client: nil,
            immediateError: runtime.tunnelState.pollBlockedReason ?? "",
            preserveUpdatedAt: true
        )
    }
}
