import SwiftUI
import ModelSwitchboardCore

extension SettingsControllerSection {
    @ViewBuilder
    var missingProfilesFolderNote: some View {
        if profilesDirectory == nil || profilesDirectory?.isEmpty == true {
            SettingsFootnote(
                text: "No profile folder reported yet. Open Profiles Folder still opens the default Application Support path.",
                color: DashboardTheme.pendingOrange
            )
        }
    }
}
