import SwiftUI

extension SettingsBehaviorSection {
    @ViewBuilder
    var launchAtLoginNotes: some View {
        if !launchAtLoginManager.isAvailable {
            SettingsFootnote(
                text: "Launch at login requires a newer macOS Service Management API.",
                color: theme.sub
            )
        }
        if launchAtLoginManager.requiresApproval {
            SettingsFootnote(
                text: "macOS needs you to approve the login item in System Settings > General > Login Items.",
                color: DashboardTheme.pendingOrange
            )
        }
        if let error = launchAtLoginManager.lastError {
            SettingsFootnote(text: error, color: DashboardTheme.stopRed)
        }
        SettingsFootnote(
            text: "The app is idle when closed in the menu bar. Open, it refreshes every 10 minutes while idle and every 10 seconds while a model is live.",
            color: theme.sub
        )
    }
}
