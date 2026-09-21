import SwiftUI
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    @ViewBuilder
    func filterChipAccessory(locked: Bool, cannotAdd: Bool) -> some View {
        if locked {
            Text("Required")
                .font(.system(size: 10))
                .foregroundStyle(theme.faint)
        } else if cannotAdd {
            Text("Max \(DashboardFilterPreferences.maxChips)")
                .font(.system(size: 10))
                .foregroundStyle(theme.faint)
        }
    }
}
