import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// Drop in-memory statuses before a force-update so the board cannot keep
    /// showing ports/models that the remote agent no longer (or never) owns.
    func discardLiveStatusForForceUpdate() {
        statuses = []
        lastUpdated = nil
        refreshState = .idle
        isRecoveringFromTransportFailure = false
        needsRefreshAgain = false
    }
}
