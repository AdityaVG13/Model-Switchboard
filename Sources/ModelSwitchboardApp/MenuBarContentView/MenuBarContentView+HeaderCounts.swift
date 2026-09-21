import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var headerCounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            (
                Text("\(hub.displayedReadyProfiles)")
                    .fontWeight(.bold)
                    .foregroundStyle(theme.label)
                + Text("/\(hub.totalProfiles)")
                    .fontWeight(.medium)
                    .foregroundStyle(theme.faint)
            )
            .font(.system(size: 22).monospacedDigit())
            Text("models ready")
                .font(.system(size: 12))
                .foregroundStyle(theme.sub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hub.displayedReadyProfiles) of \(hub.totalProfiles) models ready")
    }
}
