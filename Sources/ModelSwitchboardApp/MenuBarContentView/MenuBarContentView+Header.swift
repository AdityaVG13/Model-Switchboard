import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                headerCounts
                Spacer()
                HStack(spacing: 8) {
                    headerRefreshControl
                    if let release = updateStatus.available {
                        Link("Update \(release.version)", destination: release.url)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .accessibilityLabel("Download update \(release.version)")
                    } else {
                        Text("v\(Self.appVersion)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme.faint)
                            .accessibilityLabel("Version \(Self.appVersion)")
                    }
                }
                .task {
                    await updateStatus.checkIfDue()
                }
            }

            // Always keep This Mac utilization visible; remote host metrics
            // live in gateway section chips / Remote Hosts, not here.
            utilizationGrid

            headerFilterTabs
        }
        .padding(EdgeInsets(top: 14, leading: DashboardChromeMetrics.continuousCornerSafeInset + 2, bottom: 10, trailing: DashboardChromeMetrics.continuousCornerSafeInset + 2))
    }
}
