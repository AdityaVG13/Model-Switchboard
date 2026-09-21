import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    var listAndEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hub.remoteRuntimes.isEmpty && draft == nil {
                emptyState
            } else {
                gatewayList
            }
            if let draft {
                SettingsDivider(theme: theme)
                editor(for: draft)
            } else {
                SettingsDivider(theme: theme)
                addButton
            }
        }
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
