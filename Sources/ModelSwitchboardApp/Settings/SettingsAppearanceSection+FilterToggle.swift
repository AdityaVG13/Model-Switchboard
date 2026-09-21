import SwiftUI
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    func filterChipToggle(
        chip: DashboardFilterChip,
        selected: Bool,
        locked: Bool,
        blockAdd: Bool
    ) -> some View {
        let cannotAdd = !selected && blockAdd
        return Button {
            guard !locked, !cannotAdd else { return }
            toggleFilterChip(chip)
        } label: {
            filterChipLabel(
                chip: chip,
                selected: selected,
                locked: locked,
                cannotAdd: cannotAdd
            )
        }
        .buttonStyle(QuietCraftPressStyle())
        .disabled(locked || cannotAdd)
        .accessibilityLabel("\(chip.label) filter")
        .accessibilityHint(cannotAdd ? "Remove another filter first" : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
