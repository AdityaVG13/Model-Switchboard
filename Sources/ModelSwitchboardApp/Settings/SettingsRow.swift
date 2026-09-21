import SwiftUI

struct SettingsRow<Trailing: View>: View {
    let label: String
    let theme: DashboardTheme
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            Spacer()
            trailing
        }
        .padding(SettingsChrome.rowInsets)
    }
}
