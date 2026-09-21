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
    let features = AppFeatures.current

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

    var body: some Scene {
        menuBarScene
    }
}
