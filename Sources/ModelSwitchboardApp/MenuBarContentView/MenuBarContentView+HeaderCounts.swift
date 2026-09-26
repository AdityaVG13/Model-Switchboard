import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var headerCounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            (
                Text("\(hub.displayedReadyProfiles)")
                    .fontWeight(.bold)
                    .foregroundStyle(theme.label)
                // SF "/" sags ~6px @2x below the digit baseline; lift half
                // the dip to center it on the digit ink. (U+2215 centers
                // itself but its narrow bearings cram 22pt digits together.)
                + Text("/").baselineOffset(1.5)
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
