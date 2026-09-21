import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func footerHoldButton(
        _ title: String,
        color: Color,
        isBusy: Bool,
        disabled: Bool,
        holdHelpDetail: String?,
        action: @escaping () -> Void
    ) -> some View {
        HoldToConfirmTextButton(
            title: title,
            color: color,
            isBusy: isBusy,
            disabled: disabled,
            helpDetail: holdHelpDetail,
            action: action
        )
    }
}
