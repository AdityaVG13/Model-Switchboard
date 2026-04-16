import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

@main
struct ModelSwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("controllerBaseURL") private var controllerBaseURL = "http://127.0.0.1:8877"
    @State private var store = SwitchboardStore(controllerBaseURL: "http://127.0.0.1:8877")
    @State private var isMenuPresented = false
    @State private var statusItem: NSStatusItem?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: store,
                controllerBaseURL: $controllerBaseURL,
                reconnect: {
                    store.controllerBaseURL = controllerBaseURL
                    Task { await store.refresh() }
                },
                updateMenuBarHelp: { helpText in
                    statusItem?.button?.toolTip = helpText
                }
            )
                .onAppear {
                    if store.controllerBaseURL != controllerBaseURL {
                        store.controllerBaseURL = controllerBaseURL
                    }
                }
                .onChange(of: controllerBaseURL) { _, newValue in
                    store.controllerBaseURL = newValue
                    Task { await store.refresh() }
                }
        } label: {
            LeverSwitchIcon(
                hasReadyModels: store.summary.readyProfiles > 0,
                hasRunningModels: store.summary.runningProfiles > 0,
                size: 18
            )
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { item in
            statusItem = item
            item.button?.toolTip = store.menuBarHelp
            item.button?.setAccessibilityLabel("Model Switchboard")
        }
        .menuBarExtraStyle(.window)
    }
}
