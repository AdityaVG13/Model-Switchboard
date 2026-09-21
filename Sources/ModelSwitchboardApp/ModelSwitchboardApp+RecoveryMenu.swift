import SwiftUI
import AppKit
import ModelSwitchboardCore

extension ModelSwitchboardApp {
    func handleMenuBarPresented(_ presented: Bool) {
        // Paint host window as soon as presentation flips on - before content settles.
        if presented, let window = MenuBarExtraWindowBackdrop.menuBarExtraWindow(for: statusItem) {
            MenuBarExtraWindowBackdrop.apply(to: window)
        }
        // Login Items approval happens outside the app. Re-run registration
        // when the user opens the menu while local status is still blocked.
        if presented, localControllerNeedsRecovery {
            Task { await recoverLocalController() }
        }
    }

    var localControllerNeedsRecovery: Bool {
        if store.isRecoveringFromTransportFailure { return true }
        return store.refreshState.message != nil
    }
}
