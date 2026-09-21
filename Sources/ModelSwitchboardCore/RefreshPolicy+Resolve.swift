import Foundation

extension AutoRefreshPolicy {
    static func resolved(
        payload: ControllerStatusPayload,
        hasPendingActions: Bool,
        isRecovering: Bool
    ) -> (mode: Mode, interval: TimeInterval) {
        if hasPendingActions {
            return (.pendingAction, pendingActionInterval)
        }
        if isRecovering {
            return (.recovering, recoveringInterval)
        }
        if payload.benchmark?.running == true {
            return (.benchmarking, benchmarkingInterval)
        }
        let counts = ProfileRuntimeCounts(statuses: payload.statuses)
        if counts.running > 0 || counts.ready > 0 {
            return (.activeRuntime, activeRuntimeInterval)
        }
        return (.idle, idleInterval)
    }
}
