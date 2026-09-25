import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func applyOptimisticStopAll() -> [ModelProfileStatus] {
        noteManagedLoopbackTransition()
        rememberLastActiveProfiles(from: statuses)
        let previousStatuses = statuses
        statuses = statuses.map { $0.updating(running: false, ready: false) }
        return previousStatuses
    }

    var stoppingVisibleProfiles: Set<String> {
        Set(
            statuses.filter { ($0.running || $0.ready) && $0.isBoardVisible }.map(\.profile)
        )
    }

    var canStartQuickBenchmark: Bool {
        if benchmark?.running == true { return false }
        if benchmarkCooldownRemaining > 0 { return false }
        return true
    }
}
