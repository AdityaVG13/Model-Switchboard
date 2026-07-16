import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

@main
struct ModelSwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("controllerBaseURL") private var controllerBaseURL = "http://127.0.0.1:8877"
    @State private var controllerAuthToken: String = ""
    @AppStorage(DashboardAppearanceKeys.menuBarShowsReadyCount) private var menuBarShowsReadyCount = true
    @State private var store: SwitchboardStore
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @State private var isMenuPresented = false
    @State private var statusItem: NSStatusItem?
    private let features = AppFeatures.current

    init() {
        let registrationDiagnostic = ControllerServiceManager.shared.ensureRegistered()
        let token = Self.loadAndMigrateAuthToken()
        let baseURL = UserDefaults.standard.string(forKey: "controllerBaseURL") ?? "http://127.0.0.1:8877"
        _controllerAuthToken = State(initialValue: token)
        let initialStore = SwitchboardStore(
            controllerBaseURL: baseURL,
            controllerAuthToken: token,
            features: AppFeatures.current
        )
        if let registrationDiagnostic {
            initialStore.lastError = registrationDiagnostic
        }
        _store = State(initialValue: initialStore)
    }

    private static func loadAndMigrateAuthToken() -> String {
        let defaults = UserDefaults.standard
        let legacyKey = "controllerAuthToken"
        if let oldToken = defaults.string(forKey: legacyKey), !oldToken.isEmpty {
            KeychainTokenStorage.shared.save(oldToken)
            defaults.removeObject(forKey: legacyKey)
            return oldToken
        }
        return KeychainTokenStorage.shared.load() ?? ""
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: store,
                features: features,
                launchAtLoginManager: launchAtLoginManager,
                controllerBaseURL: $controllerBaseURL,
                controllerAuthToken: $controllerAuthToken,
                reconnect: {
                    store.controllerBaseURL = controllerBaseURL
                    store.controllerAuthToken = controllerAuthToken
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
                    if store.controllerAuthToken != controllerAuthToken {
                        store.controllerAuthToken = controllerAuthToken
                    }
                }
                .onChange(of: controllerBaseURL) { _, newValue in
                    store.controllerBaseURL = newValue
                    Task { await store.refresh() }
                }
                .onChange(of: controllerAuthToken) { _, newValue in
                    KeychainTokenStorage.shared.save(newValue)
                    store.controllerAuthToken = newValue
                    Task { await store.refresh() }
                }
        } label: {
            HStack(spacing: 3) {
                LeverSwitchIcon(
                    hasReadyModels: store.displayedReadyProfiles > 0,
                    hasRunningModels: store.displayedRunningProfiles > 0,
                    size: 18
                )
                if menuBarShowsReadyCount {
                    Text("\(store.displayedReadyProfiles)/\(store.summary.totalProfiles)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            }
            .task {
                statusItem?.button?.toolTip = store.menuBarHelp
            }
            .onChange(of: store.menuBarHelp) { _, newValue in
                statusItem?.button?.toolTip = newValue
            }
            .onChange(of: menuBarShowsReadyCount) { _, newValue in
                statusItem?.length = newValue ? NSStatusItem.variableLength : NSStatusItem.squareLength
            }
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { item in
            statusItem = item
            item.length = menuBarShowsReadyCount ? NSStatusItem.variableLength : NSStatusItem.squareLength
            item.button?.toolTip = store.menuBarHelp
            // Let SwiftUI own button contents; clearing title / forcing imageOnly
            // clips the ready-count onto neighboring menu bar items.
            item.button?.setAccessibilityLabel(features.appDisplayName)
        }
        .menuBarExtraStyle(.window)
    }
}
