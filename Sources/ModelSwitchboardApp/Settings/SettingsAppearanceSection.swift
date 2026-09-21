import SwiftUI
import ModelSwitchboardCore

struct SettingsAppearanceSection: View {
    var hub: GatewayHub?
    let theme: DashboardTheme
    let accent: Color

    @AppStorage(DashboardAppearanceKeys.theme)
    var themePreferenceRaw: String = DashboardThemePreference.system.rawValue

    @AppStorage(DashboardAppearanceKeys.accent)
    var accentRaw: String = DashboardAccent.orange.rawValue

    @AppStorage(DashboardAppearanceKeys.menuBarShowsReadyCount)
    var menuBarShowsReadyCount = true

    @AppStorage(DashboardAppearanceKeys.filterChips)
    var filterChipsRaw: String = DashboardFilterPreferences.encodeChipIDs(
        DashboardFilterPreferences.defaultChipIDs
    )

    var body: some View {
        SettingsGroup(title: "APPEARANCE", theme: theme) {
            themeRow
            SettingsDivider(theme: theme)
            accentRow
            SettingsDivider(theme: theme)
            menuBarShowsRow
            SettingsDivider(theme: theme)
            filterChipsEditor
        }
    }
}
