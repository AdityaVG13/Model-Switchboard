import SwiftUI
import ModelSwitchboardCore

struct SettingsControllerSection: View {
    @Binding var profilesDirectoryDraft: String
    let profilesDirectory: String?
    let doctorReport: DoctorReport?
    let profileDiagnostics: [ProfileDiagnostic]
    let isRunningControllerDoctor: Bool
    let theme: DashboardTheme
    let accent: Color
    let openProfilesDirectory: () -> Void
    let setProfilesDirectory: (String) async -> Void
    let openControllerRoot: () -> Void
    let runControllerDoctor: () -> Void

    var body: some View {
        SettingsGroup(title: "CONTROLLER", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsTextField(
                    label: "Profiles folder",
                    text: $profilesDirectoryDraft,
                    prompt: "~/Library/Application Support/ModelSwitchboard/Controller/model-profiles",
                    monospaced: true,
                    theme: theme
                )
                controllerFolderActions
                SettingsFootnote(
                    text: "Editable here; persisted in the controller config.json. The controller hot-reloads the folder without a restart.",
                    color: theme.sub
                )
                missingProfilesFolderNote

                SettingsDivider(theme: theme)

                doctorBlock
            }
            .padding(SettingsChrome.rowInsets)
        }
    }
}
