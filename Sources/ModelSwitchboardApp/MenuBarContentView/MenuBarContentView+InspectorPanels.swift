import SwiftUI

extension MenuBarContentView {
    @ViewBuilder
    func inspectorView(_ panel: InspectorPanel) -> some View {
        switch panel {
        case .settings:
            settingsInspector
        case .benchmarks:
            benchmarksInspector
        case .help:
            HelpView(
                exampleProfilesDirectory: store.exampleProfilesDirectoryToReveal.path,
                openExampleProfilesDirectory: store.openExampleProfilesDirectory,
                theme: theme,
                accent: accent
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
}
