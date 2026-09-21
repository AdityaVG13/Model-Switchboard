import CoreGraphics
import Foundation

extension DashboardChromeMetrics {
    /// Idle stop affordance: enabled only when something is running or a stop
    /// is already in flight (quiet disabled state when idle).
    static func canStopAnything(
        isBusy: Bool,
        storesHaveRunning: Bool,
        storesHavePending: Bool
    ) -> Bool {
        if isBusy { return true }
        return storesHaveRunning || storesHavePending
    }
}
