import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func footerPlainButton(
        _ title: String,
        color: Color,
        isBusy: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .foregroundStyle(color)
        .disabled(isBusy || disabled)
        .opacity(disabled && !isBusy ? 0.4 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(disabled ? "Nothing is running" : "")
    }
}
