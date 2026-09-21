import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    @ViewBuilder
    func footerTextButton(
        _ title: String,
        color: Color? = nil,
        isBusy: Bool = false,
        disabled: Bool = false,
        holdToConfirm: Bool = false,
        holdHelpDetail: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let resolved = color ?? theme.btnFg
        if holdToConfirm {
            footerHoldButton(
                title,
                color: resolved,
                isBusy: isBusy,
                disabled: disabled,
                holdHelpDetail: holdHelpDetail,
                action: action
            )
        } else {
            footerPlainButton(
                title,
                color: resolved,
                isBusy: isBusy,
                disabled: disabled,
                action: action
            )
        }
    }
}
