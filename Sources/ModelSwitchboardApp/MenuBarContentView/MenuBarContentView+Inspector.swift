import AppKit
import SwiftUI

extension MenuBarContentView {
    func inspectorCard(_ panel: InspectorPanel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text(panel.title)
                    .font(.system(size: 13, weight: .semibold))
                HStack {
                    Button {
                        inspectorCoordinator.requestDeferredClose(of: panel)
                        DispatchQueue.main.async {
                            let nextPanel = inspectorCoordinator.commitDeferredClose(of: panel)
                            synchronizeInspectorWindow(panel: nextPanel, refocusHostWindowOnHide: nextPanel == nil)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Close")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .accessibilityLabel("Close \(panel.title)")
                    Spacer()
                }
            }
            .padding(EdgeInsets(top: 12, leading: DashboardChromeMetrics.inspectorChromeInset(), bottom: 12, trailing: DashboardChromeMetrics.inspectorChromeInset()))
            panelDivider

            inspectorView(panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: inspectorPanelWidth, height: panelHeight, alignment: .topLeading)
        .background(theme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: DashboardChromeMetrics.continuousCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DashboardChromeMetrics.continuousCornerRadius, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
        .preferredColorScheme(themePreference.colorScheme)
    }

    @ViewBuilder
    func inspectorView(_ panel: InspectorPanel) -> some View {
        switch panel {
        case .settings:
            SettingsView(
                hub: hub,
                controllerBaseURL: $controllerBaseURL,
                controllerAuthToken: $controllerAuthToken,
                profilesDirectory: store.profilesDirectory,
                controllerRoot: store.resolvedControllerRoot,
                doctorReport: store.doctorReport,
                profileDiagnostics: store.diagnosticsNeedingAttention,
                isRunningControllerDoctor: store.isRunningControllerDoctor,
                launchAtLoginManager: launchAtLoginManager,
                theme: theme,
                accent: accent,
                appVersion: Self.appVersion,
                openProfilesDirectory: store.openProfilesDirectory,
                openControllerRoot: store.openControllerRoot,
                runControllerDoctor: {
                    Task { await store.refreshDoctorReport() }
                },
                reconnect: reconnect
            )
        case .benchmarks:
            BenchmarksPanelView(
                benchmark: store.benchmark,
                activeBenchmarkProfiles: store.activeBenchmarkProfiles,
                cooldownEndsAt: store.benchmarkCooldownEndsAt,
                remoteSections: hub.enabledRemoteRuntimes.map { runtime in
                    GatewayBenchmarkSection(
                        id: runtime.id,
                        name: runtime.name,
                        benchmark: runtime.store.benchmark,
                        activeBenchmarkProfiles: runtime.store.activeBenchmarkProfiles,
                        cooldownEndsAt: runtime.store.benchmarkCooldownEndsAt
                    )
                },
                theme: theme,
                accent: accent,
                runBenchmark: {
                    Task { await store.quickBenchmark() }
                }
            )
        case .help:
            HelpView(
                exampleProfilesDirectory: store.resolvedExampleProfilesDirectory,
                openExampleProfilesDirectory: store.openExampleProfilesDirectory
            )
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        case .remoteHosts:
            RemoteHostsPanelView(
                hub: hub,
                metricsMonitor: hostMetricsMonitor,
                theme: theme,
                accent: accent
            )
        }
    }

    func setInspectorPanel(_ nextPanel: InspectorPanel?) {
        if nextPanel == inspectorCoordinator.openPanel,
            inspectorCoordinator.deferredClosePanel != nextPanel {
            return
        }
        _ = withAnimation(inspectorAnimation) {
            inspectorCoordinator.show(nextPanel)
        }
        synchronizeInspectorWindow(panel: nextPanel)
    }

    func synchronizeInspectorWindow(
        panel: InspectorPanel? = nil,
        refocusHostWindowOnHide: Bool = false
    ) {
        guard let hostWindow else { return }
        let currentPanel = panel ?? inspectorCoordinator.openPanel
        guard let currentPanel else {
            inspectorController.hide {
                if refocusHostWindowOnHide {
                    hostWindow.makeKeyAndOrderFront(nil)
                }
            }
            return
        }

        inspectorController.show(
            title: currentPanel.title,
            parent: hostWindow,
            width: inspectorPanelWidth,
            height: panelHeight,
            gap: panelGap,
            side: sidePreference.inspectorSide,
            content: AnyView(inspectorCard(currentPanel))
        )
    }
}
