import SwiftUI
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    var filterChipsEditor: some View {
        let selectedCount = selectedFilterChipIDs.count
        let atCap = selectedCount >= DashboardFilterPreferences.maxChips
        return VStack(alignment: .leading, spacing: 8) {
            Text("Dashboard filters")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            Text("Pick up to \(DashboardFilterPreferences.maxChips) chips for the dashboard strip (\(selectedCount)/\(DashboardFilterPreferences.maxChips)). All stays pinned.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)

            filterChipToggle(chip: .all, selected: true, locked: true, blockAdd: false)
            filterChipToggle(
                chip: .running,
                selected: selectedFilterChipIDs.contains(DashboardFilterChip.running.id),
                locked: false,
                blockAdd: atCap
            )
            ForEach(availableRuntimeFilterChips) { chip in
                filterChipToggle(
                    chip: chip,
                    selected: selectedFilterChipIDs.contains(chip.id),
                    locked: false,
                    blockAdd: atCap
                )
            }
        }
        .padding(.vertical, 2)
    }
}
