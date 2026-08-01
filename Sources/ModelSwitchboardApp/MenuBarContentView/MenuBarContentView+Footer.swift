import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var footer: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left actions compress first when space is tight.
            HStack(spacing: 10) {
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
                    stopButtonTitle,
                    color: hasAnythingToStop ? DashboardTheme.stopRed : theme.faint,
                    isBusy: hub.isStopEverythingBusy,
                    disabled: !hasAnythingToStop
                ) {
                    Task { await hub.stopEverything() }
                }
                .help(stopButtonHelp)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let footerState = footerState(relativeTo: context.date) {
                    Text(footerState.label)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(footerState.color.opacity(0.16), in: Capsule())
                        .foregroundStyle(footerState.color)
                        .help(hub.menuBarHelp)
                        .padding(.horizontal, 6)
                }
            }

            // Trailing icon rail: fixed size, always fully inside the panel
            // corner radius (continuous clip eats ~12pt at the bottom-right).
            HStack(spacing: 2) {
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
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.leading, 14)
        .padding(.trailing, 14)
    }

    private var stopButtonTitle: String {
        hub.hasRemoteGateways ? "Stop Everything" : "Stop All"
    }

    private var stopButtonHelp: String {
        if !hasAnythingToStop {
            return "Nothing is running"
        }
        if hub.hasRemoteGateways {
            return "Stop every running model on this Mac and all remotes"
        }
        return "Stop every running local model"
    }

    /// True when any gateway (local or remote) still has a running process.
    var hasAnythingToStop: Bool {
        if hub.isStopEverythingBusy { return true }
        return hub.allStores.contains { store in
            store.statuses.contains(where: \.running)
                || !store.pendingProfileActions.isEmpty
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
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color ?? theme.btnFg)
        .disabled(isBusy || disabled)
        .opacity(disabled && !isBusy ? 0.4 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(disabled ? "Nothing is running" : "")
    }

    func footerIconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.faint)
                // Square hit target keeps the glyph centered away from the
                // continuous corner clip at the panel's bottom-right.
                .frame(width: 26, height: 26, alignment: .center)
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
