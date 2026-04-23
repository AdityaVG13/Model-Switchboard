import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

@main
struct ModelSwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("controllerBaseURL") private var controllerBaseURL = "http://127.0.0.1:8877"
    @State private var store = SwitchboardStore(controllerBaseURL: "http://127.0.0.1:8877", features: AppFeatures.current)
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @State private var isMenuPresented = false
    @State private var statusItem: NSStatusItem?
    private let features = AppFeatures.current

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: store,
                features: features,
                launchAtLoginManager: launchAtLoginManager,
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
                hasReadyModels: store.displayedReadyProfiles > 0,
                hasRunningModels: store.displayedRunningProfiles > 0,
                size: 18
            )
            .task {
                statusItem?.button?.toolTip = store.menuBarHelp
            }
            .onChange(of: store.menuBarHelp) { _, newValue in
                statusItem?.button?.toolTip = newValue
            }
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { item in
            statusItem = item
            item.length = NSStatusItem.squareLength
            item.button?.toolTip = store.menuBarHelp
            item.button?.title = ""
            item.button?.imagePosition = .imageOnly
            item.button?.setAccessibilityLabel(features.appDisplayName)
        }
        .menuBarExtraStyle(.window)
    }
}
