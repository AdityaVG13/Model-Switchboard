import Foundation
import ModelSwitchboardCore

/// Runs per-gateway work without MainActor isolation (safe inside `TaskGroup`).
func resolveHostMetricsEntry(
    target: RemoteHostMetricsPollTarget
) async -> (String, RemoteHostMetricsEntry) {
    if let immediate = target.immediateError {
        return (target.id, immediateHostMetricsEntry(target: target, message: immediate))
    }
    guard let client = target.client else {
        return (target.id, target.previous)
    }
    do {
        let metrics = try await client.fetchHostMetrics()
        return fetchedHostMetricsEntry(id: target.id, metrics: metrics)
    } catch {
        return (target.id, failedHostMetricsEntry(previous: target.previous, error: error))
    }
}
