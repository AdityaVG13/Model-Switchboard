import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @ViewBuilder
    func editor(for config: GatewayConfig) -> some View {
        let binding = Binding(
            get: { draft ?? config },
            set: { draft = $0 }
        )
        VStack(alignment: .leading, spacing: 8) {
            if draftIsNew {
                pairingPasteField
            }

            displayNameField(binding)
            connectionKindPicker(binding)
            connectionFields(binding)

            deployStatusText

            if !draftIsNew, let runtime = hub.runtime(id: config.id) {
                existingGatewayActions(runtime)
            }

            tokenFields

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.stopRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            editorSaveRow(for: config)
        }
        .padding(SettingsChrome.rowInsets)
    }
}
