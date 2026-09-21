import SwiftUI
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    func filterChipLabel(
        chip: DashboardFilterChip,
        selected: Bool,
        locked: Bool,
        cannotAdd: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(selected ? accent : theme.faint)
            Text(chip.label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            Spacer(minLength: 0)
            filterChipAccessory(locked: locked, cannotAdd: cannotAdd)
        }
        .contentShape(Rectangle())
        .opacity(cannotAdd ? 0.55 : 1)
    }
}
