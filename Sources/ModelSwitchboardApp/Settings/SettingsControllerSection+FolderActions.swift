import SwiftUI
import ModelSwitchboardCore

extension SettingsControllerSection {
    var controllerFolderActions: some View {
        HStack(spacing: 10) {
            SettingsLinkButton(
                title: "Save Profiles Folder",
                emphasized: true,
                theme: theme,
                accent: accent
            ) {
                Task { await setProfilesDirectory(profilesDirectoryDraft) }
            }
            SettingsLinkButton(
                title: "Open Profiles Folder",
                theme: theme,
                accent: accent,
                action: openProfilesDirectory
            )
            SettingsLinkButton(
                title: "Open Controller Root",
                theme: theme,
                accent: accent,
                action: openControllerRoot
            )
        }
    }
}
