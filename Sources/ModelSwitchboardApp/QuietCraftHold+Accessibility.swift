import SwiftUI

extension View {
    func holdConfirmAccessibility(
        title: String,
        disabled: Bool,
        isBusy: Bool,
        helpDetail: String?,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        self
            .accessibilityLabel(title)
            .accessibilityHint(
                disabled
                    ? (helpDetail ?? "Unavailable")
                    : "Hold to confirm, or activate with VoiceOver to confirm immediately"
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) {
                guard !disabled, !isBusy else { return }
                action()
            }
            .help(helpText)
    }
}
