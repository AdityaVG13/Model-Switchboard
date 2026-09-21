import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// True when hero, standby, or any remote section has a filter match.
    var boardHasAnyFilterMatch: Bool {
        if !localHeroProfiles.isEmpty || !standbyProfiles.isEmpty { return true }
        if !remoteHeroSummaries.isEmpty { return true }
        let excluded = remoteHeroProfileIDsByGateway
        for runtime in hub.enabledRemoteRuntimes {
            let excludeIDs = excluded[runtime.id] ?? []
            if runtime.store.sortedStatuses.contains(where: { status in
                if excludeIDs.contains(status.profile) { return false }
                return matchesFilter(status, in: runtime.store)
            }) {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    var modelListSection: some View {
        // Multi-gateway: if This Mac has no profiles at all, skip the empty
        // "MODELS · 0" block - remote sections already carry the list.
        // Still show a compact offline notice when the local controller failed.
        if store.sortedStatuses.isEmpty && hub.hasRemoteGateways {
            remoteOnlyLocalNotice
        } else {
            localStandbyBlock
        }
    }
}
