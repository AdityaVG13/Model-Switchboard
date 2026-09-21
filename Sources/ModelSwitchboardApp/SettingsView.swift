import SwiftUI
import ModelSwitchboardCore

struct SettingsView: View {
    var hub: GatewayHub?
    @Binding var controllerBaseURL: String
    @Binding var controllerAuthToken: String
    let profilesDirectory: String?
    let doctorReport: DoctorReport?
    let profileDiagnostics: [ProfileDiagnostic]
    let isRunningControllerDoctor: Bool
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let theme: DashboardTheme
    let accent: Color
    let appVersion: String
    let openProfilesDirectory: () -> Void
    let setProfilesDirectory: (String) async -> Void
    let openControllerRoot: () -> Void
    let runControllerDoctor: () -> Void
    let reconnect: () -> Void

    @State var profilesDirectoryDraft = ""
}
