import SwiftUI

struct SettingsLinkButton: View {
    let title: String
    var emphasized: Bool = false
    let theme: DashboardTheme
    let accent: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .semibold : .regular))
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .foregroundStyle(isEnabled ? (emphasized ? accent : theme.btnFg) : theme.faint)
    }
}
