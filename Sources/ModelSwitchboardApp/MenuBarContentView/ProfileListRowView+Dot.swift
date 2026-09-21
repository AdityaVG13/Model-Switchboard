import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    var dotColor: Color {
        switch store.profileBadgeState(for: profile, relativeTo: .now) {
        case .pending:
            return DashboardTheme.pendingOrange
        case .running:
            return DashboardTheme.runningGreen
        case .stale, .notRunning:
            return theme.dotOff
        }
    }
}
