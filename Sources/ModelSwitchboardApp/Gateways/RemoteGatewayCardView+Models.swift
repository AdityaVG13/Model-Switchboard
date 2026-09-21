import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    @ViewBuilder
    func runningModels(metrics: HostMetricsPayload?) -> some View {
        let running = runtime.store.sortedStatuses.filter {
            MenuBarContentView.isDisplayedRunning($0, in: runtime.store)
        }
        if !running.isEmpty {
            theme.line.frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("MODELS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(theme.faint)
                ForEach(running) { status in
                    runningModelRow(status, metrics: metrics)
                }
            }
        }
    }
}
