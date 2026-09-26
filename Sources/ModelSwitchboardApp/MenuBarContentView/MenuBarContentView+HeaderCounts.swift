import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var headerCounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            (
                Text("\(hub.displayedReadyProfiles)")
                    .fontWeight(.bold)
                    .foregroundStyle(theme.label)
                // U+2215 DIVISION SLASH stays inside the digit band (measured:
                // vertically centered @2x), unlike "/" which sags ~6px below
                // the digits here. No baseline lift needed.
                + Text("\u{2215}")
                    .fontWeight(.medium)
                    .foregroundStyle(theme.faint)
                + Text("\(hub.totalProfiles)")
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
