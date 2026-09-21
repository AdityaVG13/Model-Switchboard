import Foundation
import ModelSwitchboardCore

extension RemoteHostMetricsMonitor {
    func clientPollTarget(
        id: String,
        previous: Entry,
        store: SwitchboardStore
    ) -> RemoteHostMetricsPollTarget {
        do {
            return RemoteHostMetricsPollTarget(
                id: id,
                previous: previous,
                client: try store.client,
                immediateError: nil,
                preserveUpdatedAt: false
            )
        } catch {
            return RemoteHostMetricsPollTarget(
                id: id,
                previous: previous,
                client: nil,
                immediateError: SwitchboardStore.userFacingErrorDescription(for: error),
                preserveUpdatedAt: false
            )
        }
    }
}
