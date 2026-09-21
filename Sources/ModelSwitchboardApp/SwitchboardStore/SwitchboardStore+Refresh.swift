import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func refresh(includeDoctor: Bool = false) async {
        if refreshState.isInFlight {
            needsRefreshAgain = true
            return
        }
        needsRefreshAgain = false
        let previousState = refreshState
        refreshState = previousState.beginningRefresh()
        defer {
            if refreshState.isInFlight {
                refreshState = previousState
            }
            if needsRefreshAgain {
                needsRefreshAgain = false
                Task { await self.refresh(includeDoctor: includeDoctor) }
            }
        }
        do {
            try await applySuccessfulRefresh(includeDoctor: includeDoctor)
        } catch {
            applyFailedRefresh(error, previousState: previousState)
        }
    }
}
