import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    @ViewBuilder
    func remoteSectionBlock(_ section: GatewayBenchmarkSection) -> some View {
        if let latest = section.benchmark?.latest, !latest.rows.isEmpty {
            sectionHeader(section.name.uppercased())
            if section.benchmark?.running == true {
                remoteRunningNotice(section.name)
            }
            summaryCard(latest, gatewayLabel: section.name)
            rankedRows(latest, gatewayLabel: section.name)
        } else if section.benchmark?.running == true {
            sectionHeader(section.name.uppercased())
            remoteRunningNotice(section.name)
        }
    }

    func remoteRunningNotice(_ name: String) -> some View {
        noticeText("Benchmark running on " + name + "…", color: DashboardTheme.pendingOrange)
    }
}
