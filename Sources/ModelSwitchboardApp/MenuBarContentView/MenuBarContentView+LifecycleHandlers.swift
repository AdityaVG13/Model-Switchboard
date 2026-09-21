import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func handleHostWindowResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === hostWindow else { return }
        let clamped = clampPanelWidth(Double(window.frame.width))
        if abs(storedMainPanelWidth - clamped) > 0.5 {
            storedMainPanelWidth = clamped
        }
        synchronizeInspectorWindow()
    }

    func handleMenuPresentedChange(_ presented: Bool) {
        // Dismiss inspector as soon as the menu closes so a floating side
        // panel cannot keep focus and pin the dashboard open.
        if !presented {
            inspectorController.hide()
            inspectorCoordinator.reset()
        }
    }
}
