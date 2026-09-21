import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    @ViewBuilder
    var remoteOnlyLocalNotice: some View {
        if store.lastError != nil {
            emptyCopy(localEmptyMessage)
        } else if profileFilter != DashboardFilterChip.all.id, !boardHasAnyFilterMatch {
            filterMissMessage
        } else {
            EmptyView()
        }
    }

    var filterMissMessage: some View {
        emptyCopy("No models match this filter.")
    }

    func emptyCopy(_ message: String, compact: Bool = false) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(theme.sub)
            .padding(EdgeInsets(
                top: compact ? 2 : 8,
                leading: compact ? 4 : 14,
                bottom: compact ? 8 : 4,
                trailing: compact ? 4 : 14
            ))
            .fixedSize(horizontal: false, vertical: true)
    }
}
