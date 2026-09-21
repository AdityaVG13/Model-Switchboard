import Foundation
import ModelSwitchboardCore

/// Work item prepared on MainActor, executed off it in a task group.
struct RemoteHostMetricsPollTarget: Sendable {
    let id: String
    let previous: RemoteHostMetricsEntry
    /// Ready HTTP client for this gateway; nil when only an immediate result applies.
    let client: ControllerClient?
    /// Tunnel / client-build failure applied without network I/O.
    let immediateError: String?
    /// Match pre-parallel tunnel path: set error but leave `updatedAt` unchanged.
    let preserveUpdatedAt: Bool
}

extension RemoteHostMetricsMonitor {
    func pollOnce() async {
        guard let hub else { return }
        let runtimes = hub.enabledRemoteRuntimes
        dropStaleHostEntries(activeIDs: Set(runtimes.map(\.id)))

        let targets = runtimes.map { pollTarget(for: $0) }
        applyHostMetricsResults(await collectHostMetricsResults(targets))
    }

    func applyHostMetricsResults(_ results: [(String, Entry)]) {
        for (id, entry) in results {
            if entries[id] != entry {
                entries[id] = entry
            }
        }
    }
}
