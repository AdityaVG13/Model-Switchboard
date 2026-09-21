import SwiftUI
import ModelSwitchboardCore

extension RemoteHostsPanelView {
    @ViewBuilder
    var remoteHostCards: some View {
        if hub.enabledRemoteRuntimes.isEmpty {
            emptyState
        } else {
            ForEach(hub.enabledRemoteRuntimes) { runtime in
                RemoteGatewayCardView(
                    hub: hub,
                    metricsMonitor: metricsMonitor,
                    runtime: runtime,
                    entry: metricsMonitor.entry(forGatewayID: runtime.id),
                    theme: theme,
                    accent: accent,
                    renamingGatewayID: $renamingGatewayID,
                    renameDraft: $renameDraft,
                    renameError: $renameError,
                    didCopyInstallCommand: $didCopyInstallCommand,
                    hideHostInfo: hideHostInfo
                )
            }
        }
    }

    func attachAndPollMetrics() async {
        metricsMonitor.attach(hub: hub)
        metricsMonitor.start()
        await metricsMonitor.pollOnce()
    }
}
