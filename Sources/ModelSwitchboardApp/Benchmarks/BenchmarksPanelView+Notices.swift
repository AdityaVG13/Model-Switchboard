import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    @ViewBuilder
    var boardNotices: some View {
        if benchmark?.running == true {
            noticeText(activeRunLabel, color: DashboardTheme.pendingOrange)
            noticeText("The results below show the latest completed run until this benchmark finishes.", color: theme.sub)
        } else if let benchmarkCooldownLabel {
            noticeText("Benchmark cooldown: \(benchmarkCooldownLabel) remaining.", color: theme.sub)
        }

        if let exportNotice {
            noticeText(exportNotice.message, color: exportNotice.isError ? DashboardTheme.stopRed : DashboardTheme.runningGreen)
        }
    }
}
