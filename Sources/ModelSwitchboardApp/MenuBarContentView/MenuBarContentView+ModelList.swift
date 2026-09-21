import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// Local standby/models block actually paints chrome (not EmptyView).
    var showsLocalModelList: Bool {
        if store.sortedStatuses.isEmpty && hub.hasRemoteGateways {
            return store.lastError != nil
        }
        let suppressLocalBlock = standbyProfiles.isEmpty && (
            heroProfile != nil
                || (hub.hasRemoteGateways && !store.sortedStatuses.isEmpty)
        )
        return !suppressLocalBlock
    }
}
