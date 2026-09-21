import SwiftUI
import ModelSwitchboardCore

extension SettingsView {
    var settingsSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsAppearanceSection(hub: hub, theme: theme, accent: accent)
            SettingsConnectionSection(
                controllerBaseURL: $controllerBaseURL,
                controllerAuthToken: $controllerAuthToken,
                theme: theme,
                accent: accent,
                reconnect: reconnect
            )
            if let hub {
                GatewaySettingsSection(hub: hub, theme: theme, accent: accent)
            }
            SettingsBehaviorSection(
                launchAtLoginManager: launchAtLoginManager,
                theme: theme,
                accent: accent
            )
            SettingsControllerSection(
                profilesDirectoryDraft: $profilesDirectoryDraft,
                profilesDirectory: profilesDirectory,
                doctorReport: doctorReport,
                profileDiagnostics: profileDiagnostics,
                isRunningControllerDoctor: isRunningControllerDoctor,
                theme: theme,
                accent: accent,
                openProfilesDirectory: openProfilesDirectory,
                setProfilesDirectory: setProfilesDirectory,
                openControllerRoot: openControllerRoot,
                runControllerDoctor: runControllerDoctor
            )
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10))
    }
}
