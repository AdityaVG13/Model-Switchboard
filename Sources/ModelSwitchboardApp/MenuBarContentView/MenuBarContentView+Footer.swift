import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
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
                    color: hasAnythingToStop ? DashboardTheme.stopRed : theme.faint,
                    isBusy: hub.isStopEverythingBusy,
                    disabled: !hasAnythingToStop
                ) {
                    Task { await hub.stopEverything() }
                }
                .help(
                    hasAnythingToStop
                        ? (hub.hasRemoteGateways
                            ? "Stop every running model on this Mac and all remotes"
                            : "Stop every running local model")
                        : "Nothing is running"
                )
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

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

            // Fixed-width icon rail so the trailing quit control never sits
            // under the continuous corner clip of the panel.
            HStack(spacing: 4) {
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
            .layoutPriority(1)
        }
        // Extra trailing inset: continuous corner radius (~12) eats the bottom-
        // right glyph if icons are only 16pt from the edge.
        .padding(EdgeInsets(top: 9, leading: 16, bottom: 10, trailing: 20))
    }

    /// True when any gateway (local or remote) still has a running process.
    var hasAnythingToStop: Bool {
        if hub.isStopEverythingBusy { return true }
        return hub.allStores.contains { store in
            store.statuses.contains(where: \.running)
                || store.pendingProfileActions.values.contains { !$0.isEmpty }
        }
    }

    var syncableIntegrations: [ControllerIntegration] {
        store.integrations.filter { $0.capabilities.contains("sync") }
    }

    func footerTextButton(
        _ title: String,
        color: Color? = nil,
        isBusy: Bool = false,
        disabled: Bool = false,
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
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color ?? theme.btnFg)
        .disabled(isBusy || disabled)
        .opacity(disabled && !isBusy ? 0.45 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(disabled ? "Nothing is running" : "")
    }

    func footerIconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.faint)
                .frame(width: 28, height: 28)
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
