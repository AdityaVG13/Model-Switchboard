import SwiftUI

struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    var prompt: String
    var monospaced: Bool = false
    let theme: DashboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
                .foregroundStyle(theme.fieldFg)
        }
    }
}
