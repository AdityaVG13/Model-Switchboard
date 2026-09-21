import SwiftUI
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    var themeRow: some View {
        SettingsRow(label: "Theme", theme: theme) {
            SettingsSegmentedControl(
                options: DashboardThemePreference.allCases.map(\.rawValue),
                label: { option in
                    DashboardThemePreference(rawValue: option)?.label ?? option
                },
                selection: $themePreferenceRaw,
                theme: theme
            )
        }
    }

    var accentRow: some View {
        SettingsRow(label: "Accent color", theme: theme) {
            accentSwatches
        }
    }

    var menuBarShowsRow: some View {
        SettingsRow(label: "Menu bar shows", theme: theme) {
            SettingsSegmentedControl(
                options: ["icon", "count"],
                label: { $0 == "count" ? "Ready count" : "Icon" },
                selection: Binding(
                    get: { menuBarShowsReadyCount ? "count" : "icon" },
                    set: { menuBarShowsReadyCount = $0 == "count" }
                ),
                theme: theme
            )
        }
    }
}
