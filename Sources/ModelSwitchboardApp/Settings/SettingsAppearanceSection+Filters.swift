import SwiftUI
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    var selectedFilterChipIDs: [String] {
        DashboardFilterPreferences.decodeChipIDs(filterChipsRaw)
    }

    var availableRuntimeFilterChips: [DashboardFilterChip] {
        let statuses = hub?.allStores.flatMap(\.sortedStatuses) ?? []
        return DashboardFilterPreferences.availableRuntimeChips(fromStatuses: statuses)
    }
}
