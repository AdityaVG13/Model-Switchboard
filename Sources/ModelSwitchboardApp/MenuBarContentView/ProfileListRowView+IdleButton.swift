import AppKit
import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    @ViewBuilder
    var idlePrimaryButton: some View {
        if isDisplayedRunning {
            actionIcon("stop.fill", color: DashboardTheme.stopRed, label: "Stop \(profile.displayName)") {
                Task { await store.stop(profile.profile) }
            }
        } else {
            actionIcon(
                "play.fill",
                color: accent,
                label: "Activate \(profile.displayName)",
                hint: "Stops other models on this gateway, then starts this one"
            ) {
                Task { await store.activate(profile.profile) }
            }
        }
    }
}
