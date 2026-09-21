import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func freshnessLabel(_ state: (label: String, color: Color)) -> some View {
        Text(state.label)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.6)
            .lineLimit(1)
            .padding(.leading, 6)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(state.color)
                    .frame(width: 2)
            }
            .foregroundStyle(state.color)
            .help(hub.menuBarHelp)
            .padding(.horizontal, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.label == "ERROR" ? "Status error" : "Status stale")
            .accessibilityValue(hub.menuBarHelp)
    }

    func footerState(relativeTo now: Date) -> (label: String, color: Color)? {
        // With remote gateways, a dead local controller must not paint the whole
        // panel STALE while Spark (or another remote) is live.
        let states = hub.allStores.map { $0.statusFreshness(relativeTo: now) }
        if states.contains(.fresh) {
            return nil
        }
        if states.contains(.error) {
            return ("ERROR", DashboardTheme.stopRed)
        }
        // Collapse cached + stale into one quiet "STALE" signal - same urgency
        // for the operator, less chrome to parse.
        if states.contains(.cached) || states.contains(.stale) {
            return ("STALE", DashboardTheme.pendingOrange)
        }
        return nil
    }
}
