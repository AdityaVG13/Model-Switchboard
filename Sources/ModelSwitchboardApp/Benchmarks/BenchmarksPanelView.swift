import SwiftUI
import ModelSwitchboardCore

struct BenchmarksPanelView: View {
    let benchmark: BenchmarkStatus?
    let activeBenchmarkProfiles: [String]
    let cooldownEndsAt: Date?
    /// Latest results from remote gateway stores, labeled by gateway name.
    var remoteSections: [GatewayBenchmarkSection] = []
    let theme: DashboardTheme
    let accent: Color
    let runBenchmark: () -> Void
    @State var exportNotice: BenchmarkCSVExport.Notice?
    @State var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    boardNotices
                    localLatestBlock
                    remoteLatestBlocks
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)

            theme.line.frame(height: 1)
            panelFooter
        }
        .modifier(BenchmarkTickModifier(
            needsTick: needsCountdownTick,
            now: $now
        ))
    }
}
