import AppKit
import SwiftUI

extension MenuBarContentView {
    func inspectorCard(_ panel: InspectorPanel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(panel.title)
                    .font(.headline)
                Spacer()
                Button {
                    inspectorCoordinator.requestDeferredClose(of: panel)
                    DispatchQueue.main.async {
                        let nextPanel = inspectorCoordinator.commitDeferredClose(of: panel)
                        synchronizeInspectorWindow(panel: nextPanel, refocusHostWindowOnHide: nextPanel == nil)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close \(panel.title)")
            }

            inspectorView(panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(width: inspectorPanelWidth, height: panelHeight, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    func inspectorView(_ panel: InspectorPanel) -> some View {
        switch panel {
        case .settings:
            SettingsView(
                controllerBaseURL: $controllerBaseURL,
                profilesDirectory: store.profilesDirectory,
                controllerRoot: store.resolvedControllerRoot,
                doctorReport: store.doctorReport,
                profileDiagnostics: store.diagnosticsNeedingAttention,
                isRunningControllerDoctor: store.isRunningControllerDoctor,
                launchAtLoginManager: launchAtLoginManager,
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
                runBenchmark: {
                    Task { await store.quickBenchmark() }
                }
            )
        case .help:
            HelpView(
                exampleProfilesDirectory: store.resolvedExampleProfilesDirectory,
                openExampleProfilesDirectory: store.openExampleProfilesDirectory
            )
        }
    }

    func footerToggleButton(_ title: String, panel: InspectorPanel, icon: String) -> some View {
        Button {
            let nextPanel = inspectorCoordinator.toggle(panel)
            synchronizeInspectorWindow(panel: nextPanel)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }

    func footerIconToggleButton(_ title: String, panel: InspectorPanel, icon: String) -> some View {
        Button {
            let nextPanel = inspectorCoordinator.toggle(panel)
            synchronizeInspectorWindow(panel: nextPanel)
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .help(title)
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
            content: AnyView(inspectorCard(currentPanel))
        )
    }
}
