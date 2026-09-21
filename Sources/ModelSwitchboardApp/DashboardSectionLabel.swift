import SwiftUI

struct DashboardSectionLabel: View {
    let text: String
    let theme: DashboardTheme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.faint)
    }
}
