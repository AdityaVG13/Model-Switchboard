import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// Record a transient refresh/action failure unless a sticky gateway
    /// diagnostic (`.blocked`) is active - refresh failures must not clobber it.
    func recordRefreshFailure(
        _ error: Error,
        actionName: String? = nil,
        profile: String? = nil
    ) {
        if refreshState.isBlocked { return }
        noteRecoveringFrom(error)
        refreshState = .failed(
            message: Self.userFacingErrorDescription(
                for: error,
                actionName: actionName,
                status: profile.flatMap(statusForProfile),
                diagnostic: profile.flatMap(diagnosticForProfile),
                isLocal: gateway.isLocal
            )
        )
    }

    /// DNS / refused / no-route belong on the 3s recovering poll. Timeouts do
    /// not: a 45s remote `/api/status` plus a 3s retry stacks requests and
    /// flashes the menu bar on every cycle.
    func noteRecoveringFrom(_ error: Error) {
        isRecoveringFromTransportFailure =
            Self.isTransientReachabilityFailure(error) && !Self.isTimeout(error)
    }

    nonisolated static func isTransientReachabilityFailure(_ error: Error) -> Bool {
        UserFacingControllerError.isTransient(error)
    }

    nonisolated static func isTimeout(_ error: Error) -> Bool {
        UserFacingControllerError.isTimeout(error)
    }
}
