import SwiftUI

struct SettingsToggleRow: View {
    let label: String
    let subtitle: String
    @Binding var isOn: Bool
    var disabled: Bool = false
    let theme: DashboardTheme
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.label)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(accent)
                .disabled(disabled)
                .accessibilityLabel(label)
        }
    }
}
