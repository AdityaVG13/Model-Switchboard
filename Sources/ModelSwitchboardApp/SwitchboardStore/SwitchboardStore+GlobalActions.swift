import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func stopAll() async {
        guard pendingGlobalActions.insert(.stopAll).inserted else { return }
        defer { pendingGlobalActions.remove(.stopAll) }
        let stoppingProfiles = stoppingVisibleProfiles
        let previousStatuses = applyOptimisticStopAll()
        let succeeded = await run(
            { try await $0.stopAll() },
            verify: { try await self.verifyProfilesStopped(stoppingProfiles, using: $0) }
        )
        if !succeeded {
            statuses = previousStatuses
        }
    }
}
