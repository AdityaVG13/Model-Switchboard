import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func connectionKindPicker(_ binding: Binding<GatewayConfig>) -> some View {
        HStack(spacing: 8) {
            Text("Connection")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            Spacer(minLength: 0)
            SettingsSegmentedControl(
                options: [GatewayKind.ssh, .direct],
                label: { $0 == .ssh ? "SSH tunnel" : "Direct URL" },
                selection: Binding(
                    get: { binding.wrappedValue.kind },
                    set: { switchKind(&binding.wrappedValue, to: $0) }
                ),
                theme: theme
            )
        }
    }

    func editorSaveRow(for config: GatewayConfig) -> some View {
        HStack(spacing: 10) {
            linkButton("Save", emphasized: true) { save() }
            linkButton("Cancel") { closeEditor() }
            Spacer()
            if !draftIsNew {
                HoldToConfirmTextButton(
                    title: "Remove",
                    color: DashboardTheme.stopRed,
                    helpDetail: "Deletes this gateway and its keychain token"
                ) {
                    hub.removeGateway(id: config.id)
                    closeEditor()
                }
            }
        }
    }
}
