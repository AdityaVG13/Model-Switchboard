import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add any Linux or Unix host. Paste the pairing code the agent prints, or install over SSH from here.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            pairingPasteField
            HStack(spacing: 10) {
                linkButton("Add without a code…") {
                    beginManualAdd()
                }
            }
        }
        .padding(SettingsChrome.rowInsets)
    }
}
