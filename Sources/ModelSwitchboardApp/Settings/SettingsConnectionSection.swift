import SwiftUI
import ModelSwitchboardCore

struct SettingsConnectionSection: View {
    @Binding var controllerBaseURL: String
    @Binding var controllerAuthToken: String
    let theme: DashboardTheme
    let accent: Color
    let reconnect: () -> Void

    let defaultControllerBaseURL = ControllerEndpointDefaults.baseURLString

    var body: some View {
        SettingsGroup(title: "CONNECTION", theme: theme) {
            connectionFields
                .padding(SettingsChrome.rowInsets)
        }
    }
}
