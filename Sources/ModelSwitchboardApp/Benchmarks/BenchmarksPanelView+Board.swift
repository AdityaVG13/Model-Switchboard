import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    @ViewBuilder
    var localLatestBlock: some View {
        if let latest = benchmark?.latest, !latest.rows.isEmpty {
            sectionHeader("THIS MAC")
            let best = BenchmarkMetricFormatting.sortedRowsForDisplay(latest.rows).first
            summaryCard(latest, gatewayLabel: nil)
            if let cases = best?.prefillCases, !cases.isEmpty {
                prefillSection(cases)
                theme.line.frame(height: 1)
                    .padding(.bottom, 4)
            }
            rankedRows(latest, gatewayLabel: nil)
        } else if remoteSections.allSatisfy({ ($0.benchmark?.latest?.rows.isEmpty ?? true) }) {
            noticeText("No benchmark recorded yet. Run a benchmark to populate this panel.", color: theme.sub)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    var remoteLatestBlocks: some View {
        ForEach(remoteSections) { section in
            remoteSectionBlock(section)
        }
    }
}
