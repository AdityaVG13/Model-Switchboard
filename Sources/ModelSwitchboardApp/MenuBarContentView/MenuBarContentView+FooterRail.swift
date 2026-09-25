import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var footerActions: some View {
        HStack(spacing: 10) {
            footerTextButton("Benchmarks") {
                let nextPanel = inspectorCoordinator.toggle(.benchmarks)
                synchronizeInspectorWindow(panel: nextPanel)
            }

            ForEach(syncableIntegrations) { integration in
                footerTextButton(
                    integration.syncLabel ?? "Sync \(integration.displayName)",
                    isBusy: store.pendingIntegrationActions.contains(integration.id)
                ) {
                    Task { await store.runIntegration(integration) }
                }
                .help(integration.description ?? "")
            }

            footerStopButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(0)
    }
}
