import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func applyPanelLifecycle<Content: View>(_ content: Content) -> some View {
        applyPanelChrome(
            content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
                handleHostWindowResize(notification)
            }
            .task {
                startAttachedMonitors()
                updateMenuBarHelp(hub.menuBarHelp)
                synchronizeInspectorWindow()
            }
            .onChange(of: isMenuPresented) { _, presented in
                handleMenuPresentedChange(presented)
            }
            .onDisappear {
                handlePanelDisappear()
            }
            .onChange(of: hub.menuBarHelp) { _, newValue in
                updateMenuBarHelp(newValue)
            }
            .onChange(of: storedMainPanelWidth) { _, newValue in
                applyStoredWidth(newValue)
            }
        )
    }
}
