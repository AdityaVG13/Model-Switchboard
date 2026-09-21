import Foundation
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    func toggleFilterChip(_ chip: DashboardFilterChip) {
        var ids = selectedFilterChipIDs
        if ids.contains(chip.id) {
            ids.removeAll { $0 == chip.id }
        } else {
            guard ids.count < DashboardFilterPreferences.maxChips else { return }
            ids.append(chip.id)
        }
        filterChipsRaw = DashboardFilterPreferences.encodeChipIDs(ids)
    }
}
