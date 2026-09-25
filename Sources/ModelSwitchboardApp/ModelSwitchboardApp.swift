import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

@main
struct ModelSwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(ControllerEndpointDefaults.baseURLUserDefaultsKey)
    var controllerBaseURL = ControllerEndpointDefaults.baseURLString
    @State var controllerAuthToken: String = ""
    @AppStorage(DashboardAppearanceKeys.menuBarShowsReadyCount) var menuBarShowsReadyCount = true
    @State var store: SwitchboardStore
    @State var hub: GatewayHub
    @State var tokenSaveTask: Task<Void, Never>?
    @StateObject var launchAtLoginManager = LaunchAtLoginManager.shared
    @State var isMenuPresented = false
    @State var statusItem: NSStatusItem?
    @State var statusItemClickGate = StatusItemClickGate()

    init() {
        GatewayPlusMigration.importIfNeeded(to: .standard)
        // DMG-drag upgraders bypass install.sh, so the Plus login item is
        // cleaned here too: a stale Plus auto-launch would fight the unified
        // app over the menu bar and the controller port. Silent no-op when
        // Plus was never registered.
        try? LaunchAtLoginManager.shared.unregisterLegacyPlusLoginItem()
        let token = Self.loadAndMigrateAuthToken()
        let baseURL =
            UserDefaults.standard.string(forKey: ControllerEndpointDefaults.baseURLUserDefaultsKey)
            ?? ControllerEndpointDefaults.baseURLString
        _controllerAuthToken = State(initialValue: token)
        let store = SwitchboardStore(
            controllerBaseURL: baseURL,
            controllerAuthToken: token
        )
        _store = State(initialValue: store)
        _hub = State(initialValue: GatewayHub(localStore: store))
    }

    var body: some Scene {
        menuBarScene
    }
}
