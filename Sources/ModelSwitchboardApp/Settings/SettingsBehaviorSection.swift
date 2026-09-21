import SwiftUI

struct SettingsBehaviorSection: View {
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let theme: DashboardTheme
    let accent: Color

    var body: some View {
        SettingsGroup(title: "BEHAVIOR", theme: theme) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggleRow(
                    label: "Launch at login",
                    subtitle: "Start Model Switchboard with macOS",
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled || launchAtLoginManager.requiresApproval },
                        set: { launchAtLoginManager.setEnabled($0) }
                    ),
                    disabled: !launchAtLoginManager.isAvailable,
                    theme: theme,
                    accent: accent
                )
                launchAtLoginNotes
            }
            .padding(SettingsChrome.rowInsets)
        }
    }
}
