import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

extension ModelSwitchboardApp {
    var menuBarScene: some Scene {
        MenuBarExtra {
            applyMenuBarContentLifecycle(
                MenuBarContentView(
                    store: store,
                    hub: hub,
                    launchAtLoginManager: launchAtLoginManager,
                    controllerBaseURL: $controllerBaseURL,
                    controllerAuthToken: $controllerAuthToken,
                    reconnect: {
                        store.controllerBaseURL = controllerBaseURL
                        store.controllerAuthToken = controllerAuthToken
                        hub.refreshAll()
                    },
                    updateMenuBarHelp: { helpText in
                        statusItem?.button?.toolTip = helpText
                    },
                    isMenuPresented: $isMenuPresented
                )
            )
        } label: {
            menuBarLabel
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { item in
            attachStatusItem(item)
        }
        .onChange(of: isMenuPresented) { _, presented in
            handleMenuBarPresented(presented)
        }
        .menuBarExtraStyle(.window)
    }
}
