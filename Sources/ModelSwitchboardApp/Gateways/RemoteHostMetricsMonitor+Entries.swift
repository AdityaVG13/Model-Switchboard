import Foundation
import ModelSwitchboardCore

func immediateHostMetricsEntry(
    target: RemoteHostMetricsPollTarget,
    message: String
) -> RemoteHostMetricsEntry {
    var entry = target.previous
    entry.error = message
    if !target.preserveUpdatedAt {
        entry.updatedAt = Date()
    }
    return entry
}

func fetchedHostMetricsEntry(
    id: String,
    metrics: HostMetricsPayload
) -> (String, RemoteHostMetricsEntry) {
    (
        id,
        RemoteHostMetricsEntry(metrics: metrics, error: nil, updatedAt: Date(), unsupported: false)
    )
}
