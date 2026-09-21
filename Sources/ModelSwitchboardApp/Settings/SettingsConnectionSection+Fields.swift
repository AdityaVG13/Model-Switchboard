import SwiftUI
import ModelSwitchboardCore

extension SettingsConnectionSection {
    var connectionFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsTextField(
                label: "Controller base URL",
                text: $controllerBaseURL,
                prompt: defaultControllerBaseURL,
                monospaced: true,
                theme: theme
            )
            SettingsSecureField(
                label: "Bearer token (optional)",
                text: $controllerAuthToken,
                prompt: "Required for --unsafe-bind controllers",
                theme: theme
            )
            HStack(spacing: 10) {
                SettingsLinkButton(
                    title: "Use Default",
                    theme: theme,
                    accent: accent
                ) {
                    controllerBaseURL = defaultControllerBaseURL
                }
                SettingsLinkButton(
                    title: "Reconnect",
                    emphasized: true,
                    theme: theme,
                    accent: accent,
                    action: reconnect
                )
            }
            SettingsFootnote(
                text: "Use the loopback controller unless you intentionally moved the control plane to another host or port. When the controller requires auth, paste the bearer token here (never in the URL). Model paths and launch commands stay in controller profile files.",
                color: theme.sub
            )
        }
    }
}
