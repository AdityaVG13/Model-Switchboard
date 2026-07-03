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
                "Stop All",
                color: DashboardTheme.stopRed,
                isBusy: store.pendingGlobalActions.contains("stop-all")
            ) {
                Task { await store.stopAll() }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let footerState = footerState(relativeTo: context.date) {
                    Text(footerState.label)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(footerState.color.opacity(0.16), in: Capsule())
                        .foregroundStyle(footerState.color)
                        .help(store.menuBarHelp)
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
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
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
        switch store.statusFreshness(relativeTo: now) {
        case .cached:
            return ("CACHED", .orange)
        case .stale:
            return ("STALE", .orange)
        case .error:
            return ("ERROR", .red)
        case .fresh:
            return nil
        }
    }
}
