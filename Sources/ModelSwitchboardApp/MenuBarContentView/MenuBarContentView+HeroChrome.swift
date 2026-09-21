import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var reopenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTHING RUNNING")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.faint)
            heroButton(
                "Reopen Last Active",
                disabled: store.pendingGlobalActions.contains(.reopenLastActive) || store.pendingGlobalActions.contains(.stopAll)
            ) {
                Task { await store.reopenLastActive() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 0, trailing: 10))
    }
}
