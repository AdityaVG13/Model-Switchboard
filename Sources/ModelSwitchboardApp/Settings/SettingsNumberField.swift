import SwiftUI

struct SettingsNumberField: View {
    let label: String
    @Binding var value: Int
    let theme: DashboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            TextField(
                "",
                text: Binding(
                    get: { String(value) },
                    set: { value = Int($0) ?? value }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(theme.fieldFg)
            .frame(width: 90)
        }
    }
}
