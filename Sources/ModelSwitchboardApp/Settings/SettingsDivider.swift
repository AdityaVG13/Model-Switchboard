import SwiftUI

struct SettingsDivider: View {
    let theme: DashboardTheme

    var body: some View {
        theme.line
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}
