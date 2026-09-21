import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: String
    let theme: DashboardTheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardSectionLabel(text: title, theme: theme)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
