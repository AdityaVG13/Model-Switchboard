import SwiftUI

struct SettingsSecureField: View {
    let label: String
    @Binding var text: String
    var prompt: String
    let theme: DashboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            SecureField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme.fieldFg)
        }
    }
}
