import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var headerCounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Full-size "/" sags below the digit band and towers above it;
            // U+2215 centers itself but spans only ~60% of 22pt digits and
            // reads petite. A 19pt "/" spans the digit band; the lift below
            // centers it on the digit ink (tuned from @2x measurement).
            // (Plain HStack is fine here - only MenuBarExtra labels drop
            // trailing segments.)
            HStack(spacing: 1) {
                Text("\(hub.displayedReadyProfiles)")
                    .fontWeight(.bold)
                    .foregroundStyle(theme.label)
                Text("/")
                    .font(.system(size: 19).monospacedDigit())
                    .baselineOffset(2.0)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.faint)
                Text("\(hub.totalProfiles)")
                    .fontWeight(.medium)
                    .foregroundStyle(theme.faint)
            }
            .font(.system(size: 22).monospacedDigit())
            Text("models ready")
                .font(.system(size: 12))
                .foregroundStyle(theme.sub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hub.displayedReadyProfiles) of \(hub.totalProfiles) models ready")
    }
}
