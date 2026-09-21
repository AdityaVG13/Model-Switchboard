import AppKit
import SwiftUI

extension MenuBarContentView {
    func persistResizedWidth() {
        // Persist while activeResizeStartFrame is still set so onChange skips
        // setContentSize (which would undo leading-edge origin updates).
        if let hostWindow {
            let nextWidth = Double(hostWindow.frame.width)
            if abs(storedMainPanelWidth - nextWidth) > 0.5 {
                storedMainPanelWidth = nextWidth
            }
        }
        activeResizeStartFrame = nil
        synchronizeInspectorWindow()
    }

    func clampPanelWidth(_ value: Double) -> Double {
        DashboardChromeMetrics.clampPanelWidth(value)
    }

    func configureHostWindow(_ window: NSWindow) {
        // Custom edge handles own horizontal resize; native .resizable fights leading-edge pinning.
        window.styleMask.remove(.resizable)
        window.showsResizeIndicator = false
        window.minSize = NSSize(width: minMainPanelWidth, height: panelHeight)
        window.maxSize = NSSize(width: maxMainPanelWidth, height: panelHeight)
        // Solid backdrop so open/close thrash never shows clear/black chrome.
        let scheme: MenuBarExtraWindowBackdrop.ColorSchemeHint =
            resolvedColorScheme == .light ? .light : .dark
        MenuBarExtraWindowBackdrop.apply(to: window, scheme: scheme)
    }
}
