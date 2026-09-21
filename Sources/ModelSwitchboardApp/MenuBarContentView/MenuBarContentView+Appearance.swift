import SwiftUI

extension MenuBarContentView {
    var minMainPanelWidth: Double { Double(DashboardChromeMetrics.minMainPanelWidth) }
    var maxMainPanelWidth: Double { Double(DashboardChromeMetrics.maxMainPanelWidth) }
    var inspectorPanelWidth: CGFloat { DashboardChromeMetrics.inspectorPanelWidth }
    var panelHeight: CGFloat { DashboardChromeMetrics.panelHeight }

    var visibleFilterChips: [DashboardFilterChip] {
        DashboardFilterPreferences.chips(fromIDs: DashboardFilterPreferences.decodeChipIDs(filterChipsRaw))
    }

    var mainPanelWidth: CGFloat {
        CGFloat(clampPanelWidth(storedMainPanelWidth))
    }

    var themePreference: DashboardThemePreference {
        DashboardThemePreference(rawValue: themePreferenceRaw) ?? .system
    }

    var accent: Color {
        (DashboardAccent(rawValue: accentRaw) ?? .orange).color
    }

    /// Always light or dark - never nil - so MenuBarExtra semantic colors match tokens.
    var resolvedColorScheme: ColorScheme {
        themePreference.colorScheme ?? systemColorScheme
    }

    var theme: DashboardTheme {
        DashboardTheme.resolve(resolvedColorScheme)
    }
}
