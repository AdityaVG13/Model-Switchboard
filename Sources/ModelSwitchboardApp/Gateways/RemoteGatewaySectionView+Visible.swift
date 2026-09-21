import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewaySectionView {
    var visibleProfiles: [ModelProfileStatus] {
        store.sortedStatuses.filter { status in
            if excludeProfileIDs.contains(status.profile) {
                return false
            }
            return DashboardFilterPreferences.matches(
                status,
                filterID: filter,
                isDisplayedRunning: MenuBarContentView.isDisplayedRunning(status, in: store),
                isBusy: store.isBusy(profile: status.profile)
            )
        }
    }

    var shouldShowSection: Bool {
        !visibleProfiles.isEmpty
            || store.sortedStatuses.isEmpty
            || connectionIssue != nil
            || !excludeProfileIDs.isEmpty
    }
}
