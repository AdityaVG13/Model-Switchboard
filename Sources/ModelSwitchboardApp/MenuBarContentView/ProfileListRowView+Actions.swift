import AppKit
import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    @ViewBuilder
    var primaryButton: some View {
        if isBusy {
            iconContainer {
                ProgressView()
                    .controlSize(.mini)
            }
            .accessibilityLabel(
                pending.map { "\($0) \(profile.displayName)" } ?? "Working on \(profile.displayName)"
            )
        } else {
            idlePrimaryButton
        }
    }
}
