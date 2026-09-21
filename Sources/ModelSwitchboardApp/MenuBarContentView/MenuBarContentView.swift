import AppKit
import SwiftUI
import ModelSwitchboardCore

struct MenuBarContentView: View {
    /// Selection id for the dashboard filter strip (`all` / `running` / `runtime:…`).
    typealias ProfileFilter = String

    @Bindable var store: SwitchboardStore
    @Bindable var hub: GatewayHub
    let features: AppFeatures
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @Binding var controllerBaseURL: String
    @Binding var controllerAuthToken: String
    let reconnect: () -> Void
    let updateMenuBarHelp: (String) -> Void
    /// When false, deferred teardown may run after hide debounce.
    /// Binding so onDisappear / onChange always see live presentation state.
    @Binding var isMenuPresented: Bool

    init(
        store: SwitchboardStore,
        hub: GatewayHub? = nil,
        features: AppFeatures,
        launchAtLoginManager: LaunchAtLoginManager,
        controllerBaseURL: Binding<String>,
        controllerAuthToken: Binding<String>,
        reconnect: @escaping () -> Void,
        updateMenuBarHelp: @escaping (String) -> Void,
        isMenuPresented: Binding<Bool> = .constant(true),
        systemMetrics: SystemMetricsMonitor? = nil
    ) {
        self.store = store
        self.hub = hub ?? GatewayHub(localStore: store)
        self.features = features
        self.launchAtLoginManager = launchAtLoginManager
        self._controllerBaseURL = controllerBaseURL
        self._controllerAuthToken = controllerAuthToken
        self.reconnect = reconnect
        self.updateMenuBarHelp = updateMenuBarHelp
        self._isMenuPresented = isMenuPresented
        self._systemMetrics = StateObject(wrappedValue: systemMetrics ?? SystemMetricsMonitor())
    }

    @AppStorage("menuPanelWidth")
    var storedMainPanelWidth: Double = 400

    @AppStorage(DashboardAppearanceKeys.theme)
    var themePreferenceRaw: String = DashboardThemePreference.system.rawValue

    @AppStorage(DashboardAppearanceKeys.accent)
    var accentRaw: String = DashboardAccent.orange.rawValue

    @Environment(\.colorScheme) var systemColorScheme

    let panelGap: CGFloat = 10
    let inspectorAnimation = Animation.easeInOut(duration: 0.2)

    @State var profileFilter: ProfileFilter = DashboardFilterChip.all.id

    @AppStorage(DashboardAppearanceKeys.filterChips)
    var filterChipsRaw: String = DashboardFilterPreferences.encodeChipIDs(
        DashboardFilterPreferences.defaultChipIDs
    )

    @State var inspectorCoordinator = InspectorPanelCoordinator<InspectorPanel>()
    @State var hostWindow: NSWindow?
    @State var inspectorController = InspectorPanelController()
    @StateObject var systemMetrics: SystemMetricsMonitor
    @State var hostMetricsMonitor = RemoteHostMetricsMonitor()
    @State var activeResizeStartFrame: NSRect?
}
