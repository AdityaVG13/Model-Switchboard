import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var headerRefreshControl: some View {
        // Keep a fixed-size control: swapping ProgressView for the
        // button reflows the header and flashes the transparent
        // MenuBarExtra window (black flicker on spam-refresh).
        let isRefreshing = hub.allStores.contains(where: \.isRefreshing)
        return Button {
            hub.refreshAll()
        } label: {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.faint)
                    .opacity(isRefreshing ? 0 : 1)
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .frame(width: DashboardChromeMetrics.footerIconHitSize, height: DashboardChromeMetrics.footerIconHitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .disabled(isRefreshing)
        .accessibilityLabel(isRefreshing ? "Refreshing" : "Refresh")
        .help(isRefreshing ? "Refresh in progress" : "Refresh all gateways")
        .transaction { $0.animation = nil }
    }
}
