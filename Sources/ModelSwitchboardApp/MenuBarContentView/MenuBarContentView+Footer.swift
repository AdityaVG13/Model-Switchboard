import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var footer: some View {
        HStack(spacing: 14) {
            if features.supportsBenchmarks {
                footerTextButton("Benchmarks") {
                    let nextPanel = inspectorCoordinator.toggle(.benchmarks)
                    synchronizeInspectorWindow(panel: nextPanel)
                }
            }

            if features.supportsIntegrations {
                ForEach(syncableIntegrations) { integration in
                    footerTextButton(
                        integration.syncLabel ?? "Sync \(integration.displayName)",
                        isBusy: store.pendingIntegrationActions.contains(integration.id)
                    ) {
                        Task { await store.runIntegration(integration) }
                    }
                    .help(integration.description ?? "")
                }
            }

            footerTextButton(
                hub.hasRemoteGateways ? "Stop Everything" : "Stop All",
                color: DashboardTheme.stopRed,
                isBusy: hub.isStopEverythingBusy
            ) {
                Task { await hub.stopEverything() }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let footerState = footerState(relativeTo: context.date) {
                    Text(footerState.label)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(footerState.color.opacity(0.16), in: Capsule())
                        .foregroundStyle(footerState.color)
                        .help(hub.menuBarHelp)
                }
            }

            HStack(spacing: 12) {
                footerIconButton("questionmark.circle", label: "Help") {
                    let nextPanel = inspectorCoordinator.toggle(.help)
                    synchronizeInspectorWindow(panel: nextPanel)
                }
                footerIconButton("gearshape", label: "Settings") {
                    let nextPanel = inspectorCoordinator.toggle(.settings)
                    synchronizeInspectorWindow(panel: nextPanel)
                }
                footerIconButton("power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
    }

    var syncableIntegrations: [ControllerIntegration] {
        store.integrations.filter { $0.capabilities.contains("sync") }
    }

    func footerTextButton(
        _ title: String,
        color: Color? = nil,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color ?? theme.btnFg)
        .disabled(isBusy)
        .accessibilityLabel(title)
    }

    func footerIconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.faint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    func footerState(relativeTo now: Date) -> (label: String, color: Color)? {
        // With remote gateways, a dead local controller must not paint the whole
        // panel STALE while Spark (or another remote) is live.
        let states = hub.allStores.map { $0.statusFreshness(relativeTo: now) }
        if states.contains(.fresh) {
            return nil
        }
        if states.contains(.cached) {
            return ("CACHED", .orange)
        }
        if states.contains(.stale) {
            return ("STALE", .orange)
        }
        if states.contains(.error) {
            return ("ERROR", .red)
        }
        return nil
    }
}
