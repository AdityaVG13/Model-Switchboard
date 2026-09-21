import Foundation
import ModelSwitchboardCore

func failedHostMetricsEntry(previous: RemoteHostMetricsEntry, error: Error) -> RemoteHostMetricsEntry {
    let message = SwitchboardStore.userFacingErrorDescription(for: error)
    let unsupported = isUnsupportedHostMetrics(error)
    var entry = previous
    entry.error = unsupported
        ? "This remote agent does not expose host metrics yet (needs upgrade for GPU/VRAM)."
        : message
    entry.unsupported = unsupported
    entry.updatedAt = Date()
    // Keep last good metrics when a transient poll fails.
    return entry
}

func isUnsupportedHostMetrics(_ error: Error) -> Bool {
    if case .httpError(let status, _) = error as? ControllerClientError {
        return status == 404
    }
    return false
}
