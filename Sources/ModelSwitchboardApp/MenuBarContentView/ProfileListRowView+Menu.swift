import AppKit
import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    var rowMenu: some View {
        Menu {
            Button("Start without stopping others") {
                Task { await store.start(profile.profile) }
            }
            .disabled(isBusy || profile.running)
            Button("Restart") {
                Task { await store.restart(profile.profile) }
            }
            .disabled(isBusy)
            if store.features.supportsBenchmarks {
                Divider()
                benchmarkMenuItems
            }
            Divider()
            copyEndpointButton
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.sub)
                .frame(width: 26, height: 26)
                .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More actions for \(profile.displayName)")
    }
}
