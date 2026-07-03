import AppKit
import SwiftUI

extension MenuBarContentView {
    var footer: some View {
        HStack(spacing: 8) {
            footerToggleButton("Settings", panel: .settings, icon: "slider.horizontal.3")
            footerSeparator()
            footerToggleButton("Help", panel: .help, icon: "questionmark.circle")
            if features.supportsBenchmarks {
                footerSeparator()
                footerIconToggleButton("Benchmarks", panel: .benchmarks, icon: "chart.xyaxis.line")
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    if let footerState = footerState(relativeTo: context.date) {
                        Text(footerState.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(footerState.color.opacity(0.16), in: Capsule())
                            .foregroundStyle(footerState.color)
                    }
                    Text(Self.clockFormatter.string(from: context.date))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func footerSeparator() -> some View {
        Text("|")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    func footerState(relativeTo now: Date) -> (label: String, color: Color)? {
        switch store.statusFreshness(relativeTo: now) {
        case .cached:
            return ("CACHED", .orange)
        case .stale:
            return ("STALE", .orange)
        case .error:
            return ("ERROR", .red)
        case .fresh:
            return nil
        }
    }
}
