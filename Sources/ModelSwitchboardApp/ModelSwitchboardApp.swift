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
    @State private var statusItemClickGate = StatusItemClickGate()
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
        let keychain = KeychainTokenStorage.shared.load() ?? ""
        if let oldToken = defaults.string(forKey: legacyKey), !oldToken.isEmpty {
            defaults.removeObject(forKey: legacyKey)
            if !keychain.isEmpty {
                return keychain
            }
            KeychainTokenStorage.shared.save(oldToken)
            return oldToken
        }
        return keychain
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
                },
                isMenuPresented: $isMenuPresented
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
                    Task { await store.refresh(includeDoctor: true) }
                }
                .onChange(of: controllerAuthToken) { _, newValue in
                    // Debounced: this fires per keystroke while typing a token.
                    tokenSaveTask?.cancel()
                    tokenSaveTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Debounced empty save clears the keychain so an intentional
                        // clear/rotate-to-no-auth sticks across relaunch.
                        KeychainTokenStorage.shared.save(trimmed)
                        store.controllerAuthToken = newValue
                        await store.refresh(includeDoctor: true)
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
                await recoverLocalController()
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
            item.button?.toolTip = hub.menuBarHelp
            // Let SwiftUI own button contents; clearing title / forcing imageOnly
            // clips the ready-count onto neighboring menu bar items.
            item.button?.setAccessibilityLabel(features.appDisplayName)
            // Rate-limit spam clicks on the menu bar icon (black-flash thrash).
            statusItemClickGate.attach(to: item)
        }
        .onChange(of: isMenuPresented) { _, presented in
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
        .menuBarExtraStyle(.window)
    }

    private var localControllerNeedsRecovery: Bool {
        if store.isRecoveringFromTransportFailure { return true }
        return store.refreshState.message != nil
    }

    /// Bootstrap diagnostics concern the local LaunchAgent only;
    /// remote gateway stores must never inherit them.
    private func recoverLocalController() async {
        let diagnostic = await ControllerServiceManager.shared.ensureRegistered()
        store.applyBootstrapDiagnostic(diagnostic)
        // Auto-refresh already fired from store init, often before the
        // LaunchAgent is listening after a crash/reboot. Poll again
        // once registration has had a chance to bring the port up.
        if diagnostic == nil {
            await store.refresh(includeDoctor: true)
        }
    }
}
