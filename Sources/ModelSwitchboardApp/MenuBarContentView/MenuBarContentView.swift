import AppKit
import SwiftUI
import ModelSwitchboardCore

struct MenuBarContentView: View {
    enum InspectorPanel: String, Identifiable {
        case settings
        case help
        case benchmarks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .settings: "Settings"
            case .help: "Help"
            case .benchmarks: "Benchmarks"
            }
        }
    }

    @Bindable var store: SwitchboardStore
    let features: AppFeatures
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @Binding var controllerBaseURL: String
    let reconnect: () -> Void
    let updateMenuBarHelp: (String) -> Void

    @AppStorage("menuPanelWidth")
    var storedMainPanelWidth: Double = 470

    let minMainPanelWidth: Double = 390
    let maxMainPanelWidth: Double = 620
    let inspectorPanelWidth: CGFloat = 290
    let panelHeight: CGFloat = 620
    let panelGap: CGFloat = 10
    let inspectorAnimation = Animation.easeInOut(duration: 0.2)

    @State var inspectorCoordinator = InspectorPanelCoordinator<InspectorPanel>()
    @State var hostWindow: NSWindow?
    @State var inspectorController = InspectorPanelController()
    @StateObject var systemMetrics = SystemMetricsMonitor()
    @State var activeResizeStartFrame: NSRect?

    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone = .current
        return formatter
    }()

    static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()

    var mainPanelWidth: CGFloat {
        CGFloat(clampPanelWidth(storedMainPanelWidth))
    }

    var body: some View {
        mainPanelCard
            .frame(width: mainPanelWidth, height: panelHeight)
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
            updateMenuBarHelp(store.menuBarHelp)
            synchronizeInspectorWindow()
        }
        .onDisappear {
            systemMetrics.stop()
            inspectorController.hide()
            inspectorCoordinator.reset()
        }
        .onChange(of: store.menuBarHelp) { _, newValue in
            updateMenuBarHelp(newValue)
        }
        .onChange(of: storedMainPanelWidth) { _, newValue in
            let clamped = clampPanelWidth(newValue)
            if abs(clamped - newValue) > .ulpOfOne {
                storedMainPanelWidth = clamped
                return
            }
            if let hostWindow {
                let nextWidth = CGFloat(clamped)
                if abs(hostWindow.frame.width - nextWidth) > 0.5, !hostWindow.inLiveResize {
                    hostWindow.setContentSize(NSSize(width: nextWidth, height: panelHeight))
                }
            }
            synchronizeInspectorWindow()
        }
        .animation(inspectorAnimation, value: inspectorCoordinator.openPanel)
        .animation(.snappy(duration: 0.18), value: store.pendingProfileActions)
        .animation(.snappy(duration: 0.18), value: store.pendingGlobalActions)
    }
}
