import SwiftUI

extension HoldToConfirmTextButton {
    var body: some View {
        HStack(spacing: 4) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(title)
                .font(.system(size: 11.5, weight: labelWeight))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .padding(.horizontal, fillsWidth ? 0 : 4)
        .padding(.vertical, fillsWidth ? 6 : 2)
        .frame(minHeight: fillsWidth ? nil : 24)
        .background { progressBackground }
        .clipShape(RoundedRectangle(cornerRadius: fillsWidth ? 7 : 4, style: .continuous))
        .contentShape(Rectangle())
        .foregroundStyle(labelColor)
        .opacity(disabled && !isBusy ? 0.4 : 1)
        .scaleEffect(isHolding && !reduceMotion ? 0.97 : 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isHolding
        )
        .gesture(holdDragGesture)
        .disabled(isBusy || disabled)
        .holdConfirmAccessibility(
            title: title,
            disabled: disabled,
            isBusy: isBusy,
            helpDetail: helpDetail,
            helpText: helpText,
            action: action
        )
        .onDisappear { cancelHold() }
    }
}
