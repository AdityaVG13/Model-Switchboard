import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func handlePanelDisappear() {
        // Spam-toggling the status item can fire disappear/appear within a
        // few hundred ms. Tear down monitors only if we stay closed.
        inspectorController.hide()
        inspectorCoordinator.reset()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !isMenuPresented else { return }
            systemMetrics.stop()
            hostMetricsMonitor.stop()
        }
    }

    func handleThemePreferenceChange() {
        if let hostWindow { configureHostWindow(hostWindow) }
        synchronizeInspectorWindow()
    }

    func handleSystemColorSchemeChange() {
        if themePreference.colorScheme == nil, let hostWindow {
            configureHostWindow(hostWindow)
        }
        synchronizeInspectorWindow()
    }
}
