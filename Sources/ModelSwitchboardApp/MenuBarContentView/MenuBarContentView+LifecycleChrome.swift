import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func applyPanelChrome<Content: View>(_ content: Content) -> some View {
        content
        .modifier(MenuBarPanelChrome(
            inspectorAnimation: inspectorAnimation,
            inspectorOpenPanel: inspectorCoordinator.openPanel,
            pendingProfileActions: store.pendingProfileActions,
            pendingGlobalActions: store.pendingGlobalActions,
            statusCount: store.statuses.count,
            resolvedColorScheme: resolvedColorScheme
        ))
        .onChange(of: themePreferenceRaw) { _, _ in
            handleThemePreferenceChange()
        }
        .onChange(of: systemColorScheme) { _, _ in
            handleSystemColorSchemeChange()
        }
        .onChange(of: hub.hasRemoteGateways) { _, hasRemotes in
            syncHostMetricsMonitor(hasRemotes: hasRemotes)
        }
    }
}
