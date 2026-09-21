import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        monospaced: Bool = false
    ) -> some View {
        SettingsTextField(label: label, text: text, prompt: prompt, monospaced: monospaced, theme: theme)
    }

    func numberField(_ label: String, value: Binding<Int>) -> some View {
        SettingsNumberField(label: label, value: value, theme: theme)
    }

    func linkButton(
        _ title: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        SettingsLinkButton(title: title, emphasized: emphasized, theme: theme, accent: accent, action: action)
    }

    func closeEditor() {
        draft = nil
        draftToken = ""
        draftIsNew = false
        linkCode = ""
        validationMessage = nil
        deployState = .idle
        deployWithTailscale = false
    }
}
