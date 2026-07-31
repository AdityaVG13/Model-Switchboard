import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

@main
struct ModelSwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(ControllerEndpointDefaults.baseURLUserDefaultsKey)
    private var controllerBaseURL = ControllerEndpointDefaults.baseURLString
    @State private var controllerAuthToken: String = ""
    @AppStorage(DashboardAppearanceKeys.menuBarShowsReadyCount) private var menuBarShowsReadyCount = true
    @State private var store: SwitchboardStore
    @State private var hub: GatewayHub
    @State private var tokenSaveTask: Task<Void, Never>?
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @State private var isMenuPresented = false
    @State private var statusItem: NSStatusItem?
    private let features = AppFeatures.current

    init() {
        let token = Self.loadAndMigrateAuthToken()
        let baseURL =
            UserDefaults.standard.string(forKey: ControllerEndpointDefaults.baseURLUserDefaultsKey)
            ?? ControllerEndpointDefaults.baseURLString
        _controllerAuthToken = State(initialValue: token)
        let store = SwitchboardStore(
            controllerBaseURL: baseURL,
            controllerAuthToken: token,
            features: AppFeatures.current
        )
        _store = State(initialValue: store)
        _hub = State(initialValue: GatewayHub(localStore: store))
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
                hub: hub,
                features: features,
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
                    // Debounced: this fires per keystroke while typing a token.
                    tokenSaveTask?.cancel()
                    tokenSaveTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        KeychainTokenStorage.shared.save(newValue)
                        store.controllerAuthToken = newValue
                        await store.refresh()
                    }
                }
        } label: {
            HStack(spacing: 3) {
                LeverSwitchIcon(
                    hasReadyModels: hub.displayedReadyProfiles > 0,
                    hasRunningModels: hub.displayedRunningProfiles > 0,
                    size: 18
                )
                if menuBarShowsReadyCount {
                    Text("\(hub.displayedReadyProfiles)/\(hub.totalProfiles)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            }
            .task {
                statusItem?.button?.toolTip = hub.menuBarHelp
                // Bootstrap diagnostics concern the local LaunchAgent only;
                // remote gateway stores must never inherit them.
                store.applyBootstrapDiagnostic(
                    await ControllerServiceManager.shared.ensureRegistered()
                )
            }
            .onChange(of: hub.menuBarHelp) { _, newValue in
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
