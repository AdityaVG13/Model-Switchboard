import SwiftUI
import ModelSwitchboardCore

/// Settings group for remote gateways: list, connection state, and an inline
/// add/edit form (the settings panel is a side panel, so no sheets).
struct GatewaySettingsSection: View {
    @Bindable var hub: GatewayHub
    let theme: DashboardTheme
    let accent: Color

    static let installOneLiner = RemoteAgentInstallCopy.oneLiner

    @State var draft: GatewayConfig?
    @State var draftToken = ""
    @State var draftIsNew = false
    @State var linkCode = ""
    @State var validationMessage: String?
    @State var deployState: DeployState = .idle
    @State var deployWithTailscale = false
    @State var renamingGatewayID: String?
    @State var renameDraft = ""
    @State var profilesDirectoryDraft = ""
    @AppStorage(DisplayPrivacy.defaultsKey) var hideHostInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardSectionLabel(text: "REMOTE GATEWAYS", theme: theme)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 4))

            Toggle(isOn: $hideHostInfo) {
                Text("Hide hosts and addresses")
                    .font(.system(size: 10.5))
            }
            .toggleStyle(.checkbox)
            .padding(EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 4))

            listAndEditor
        }
        .padding(.bottom, 12)
    }
}
