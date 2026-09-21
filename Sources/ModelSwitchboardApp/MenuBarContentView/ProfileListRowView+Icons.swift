import AppKit
import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    func actionIcon(
        _ systemName: String,
        color: Color,
        label: String,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconContainer {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(QuietCraftPressStyle())
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
    }

    func iconContainer(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: 26, height: 26)
            .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
    }
}
