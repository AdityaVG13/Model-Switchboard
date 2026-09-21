import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    var tokenFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsSecureField(
                label: "Bearer token",
                text: $draftToken,
                prompt: tokenFieldPrompt,
                theme: theme
            )
            Text(tokenFieldHelp)
                .font(.system(size: 10))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
