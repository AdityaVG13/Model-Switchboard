import AppKit
import SwiftUI
import ModelSwitchboardCore

struct MenuBarContentView: View {
    /// Selection id for the dashboard filter strip (`all` / `running` / `runtime:…`).
    typealias ProfileFilter = String

    enum InspectorPanel: String, Identifiable {
        case settings
        case help
        case benchmarks
        case remoteHosts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .settings: "Settings"
            case .help: "Help"
            case .benchmarks: "Benchmarks"
            case .remoteHosts: "Remote Hosts"
            }
        }
    }

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

    var minMainPanelWidth: Double { Double(DashboardChromeMetrics.minMainPanelWidth) }
    var maxMainPanelWidth: Double { Double(DashboardChromeMetrics.maxMainPanelWidth) }
    var inspectorPanelWidth: CGFloat { DashboardChromeMetrics.inspectorPanelWidth }
    var panelHeight: CGFloat { DashboardChromeMetrics.panelHeight }
    let panelGap: CGFloat = 10
    let inspectorAnimation = Animation.easeInOut(duration: 0.2)

    @State var profileFilter: ProfileFilter = DashboardFilterChip.all.id

    @AppStorage(DashboardAppearanceKeys.filterChips)
    var filterChipsRaw: String = DashboardFilterPreferences.encodeChipIDs(
        DashboardFilterPreferences.defaultChipIDs
    )

    var visibleFilterChips: [DashboardFilterChip] {
        DashboardFilterPreferences.chips(fromIDs: DashboardFilterPreferences.decodeChipIDs(filterChipsRaw))
    }

    @State var inspectorCoordinator = InspectorPanelCoordinator<InspectorPanel>()
    @State var hostWindow: NSWindow?
    @State var inspectorController = InspectorPanelController()
    @StateObject var systemMetrics: SystemMetricsMonitor
    @State var hostMetricsMonitor = RemoteHostMetricsMonitor()
    @State var activeResizeStartFrame: NSRect?

    static let appVersion: String = {
        // Override hook for preview/screenshot tooling running outside the app bundle.
        if let override = ProcessInfo.processInfo.environment["MSW_VERSION_OVERRIDE"], !override.isEmpty {
            return override
        }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()

    var mainPanelWidth: CGFloat {
        CGFloat(clampPanelWidth(storedMainPanelWidth))
    }

    var themePreference: DashboardThemePreference {
        DashboardThemePreference(rawValue: themePreferenceRaw) ?? .system
    }

    var accent: Color {
        (DashboardAccent(rawValue: accentRaw) ?? .orange).color
    }

    /// Always light or dark — never nil — so MenuBarExtra semantic colors match tokens.
    var resolvedColorScheme: ColorScheme {
        themePreference.colorScheme ?? systemColorScheme
    }

    var theme: DashboardTheme {
        DashboardTheme.resolve(resolvedColorScheme)
    }

    var body: some View {
        mainPanelCard
            .frame(width: mainPanelWidth, height: panelHeight)
            .introspectMenuBarExtraWindow { window in
                MenuBarExtraWindowBackdrop.apply(to: window)
                if hostWindow !== window { hostWindow = window }
                configureHostWindow(window)
            }
            .background(
                WindowAccessor { window in
                    guard let window else { return }
                    if hostWindow !== window {
                        hostWindow = window
                    }
                    configureHostWindow(window)
                    synchronizeInspectorWindow()
                }
            )
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === hostWindow else { return }
            let clamped = clampPanelWidth(Double(window.frame.width))
            if abs(storedMainPanelWidth - clamped) > 0.5 {
                storedMainPanelWidth = clamped
            }
            synchronizeInspectorWindow()
        }
        .task {
            if features.supportsBenchmarks {
                systemMetrics.start()
            } else {
                systemMetrics.stop()
            }
            hostMetricsMonitor.attach(hub: hub)
            if hub.hasRemoteGateways {
                hostMetricsMonitor.start()
            } else {
                hostMetricsMonitor.stop()
            }
            updateMenuBarHelp(hub.menuBarHelp)
            synchronizeInspectorWindow()
        }
        .onChange(of: isMenuPresented) { _, presented in
            // Dismiss inspector as soon as the menu closes so a floating side
            // panel cannot keep focus and pin the dashboard open.
            if !presented {
                inspectorController.hide()
                inspectorCoordinator.reset()
            }
        }
        .onDisappear {
            // Spam-toggling the status item can fire disappear/appear within a
            // few hundred ms. Tear down monitors only if we stay closed.
            inspectorController.hide()
            inspectorCoordinator.reset()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !isMenuPresented else { return }
                systemMetrics.stop()
                hostMetricsMonitor.stop()
            }
        }
        .onChange(of: hub.menuBarHelp) { _, newValue in
            updateMenuBarHelp(newValue)
        }
        .onChange(of: storedMainPanelWidth) { _, newValue in
            let clamped = clampPanelWidth(newValue)
            if abs(clamped - newValue) > .ulpOfOne {
                storedMainPanelWidth = clamped
                return
            }
            // While dragging (and during the end-of-drag AppStorage write), skip
            // setContentSize -- it pins the leading edge and undoes origin updates.
            if activeResizeStartFrame != nil { return }
            if let hostWindow {
                let nextWidth = CGFloat(clamped)
                if abs(hostWindow.frame.width - nextWidth) > 0.5, !hostWindow.inLiveResize {
                    hostWindow.setContentSize(NSSize(width: nextWidth, height: panelHeight))
                }
            }
            synchronizeInspectorWindow()
        }
        .animation(inspectorAnimation, value: inspectorCoordinator.openPanel)
        // Scope snappy animations to pending action chrome only — do not animate
        // full status list replacements (causes black flicker in MenuBarExtra).
        .animation(.snappy(duration: 0.18), value: store.pendingProfileActions)
        .animation(.snappy(duration: 0.18), value: store.pendingGlobalActions)
        .transaction(value: store.statuses.count) { transaction in
            // Status payload apply should be instant; never crossfade the panel.
            if transaction.animation != nil {
                transaction.animation = nil
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .onChange(of: themePreferenceRaw) { _, _ in
            if let hostWindow { configureHostWindow(hostWindow) }
            synchronizeInspectorWindow()
        }
        .onChange(of: systemColorScheme) { _, _ in
            if themePreference.colorScheme == nil, let hostWindow {
                configureHostWindow(hostWindow)
            }
            synchronizeInspectorWindow()
        }
        .onChange(of: hub.hasRemoteGateways) { _, hasRemotes in
            hostMetricsMonitor.attach(hub: hub)
            if hasRemotes {
                hostMetricsMonitor.start()
            } else {
                hostMetricsMonitor.stop()
            }
        }
    }
}
