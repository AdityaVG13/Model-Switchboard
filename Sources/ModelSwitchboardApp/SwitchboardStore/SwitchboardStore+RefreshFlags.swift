import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var autoRefreshPolicy: AutoRefreshPolicy {
        AutoRefreshPolicy(
            payload: currentPayload,
            hasPendingActions: hasPendingActions,
            isRecovering: isRecoveringFromTransportFailure
        )
    }

    /// Derived view convenience: the user-facing error message when the refresh
    /// state holds one. Read-only projection of `refreshState` - not a slot.
    var lastError: String? {
        refreshState.message
    }

    /// Derived view convenience: a refresh is in flight.
    var isRefreshing: Bool {
        refreshState.isInFlight
    }

    var hasPendingActions: Bool {
        !pendingProfileActions.isEmpty ||
            !pendingGlobalActions.isEmpty ||
            !pendingIntegrationActions.isEmpty
    }
}
