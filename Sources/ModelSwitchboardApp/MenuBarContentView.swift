import AppKit
import SwiftUI
import ModelSwitchboardCore

struct MenuBarContentView: View {
    private enum InspectorPanel: String, Identifiable {
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
    private var storedMainPanelWidth: Double = 470

    private let minMainPanelWidth: Double = 390
    private let maxMainPanelWidth: Double = 620
    private let inspectorPanelWidth: CGFloat = 290
    private let panelHeight: CGFloat = 620
    private let panelGap: CGFloat = 10
    private let inspectorAnimation = Animation.easeInOut(duration: 0.2)

    @State private var inspectorCoordinator = InspectorPanelCoordinator<InspectorPanel>()
    @State private var hostWindow: NSWindow?
    @State private var inspectorController = InspectorPanelController()
    @StateObject private var systemMetrics = SystemMetricsMonitor()
    @State private var activeResizeStartFrame: NSRect?

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone = .current
        return formatter
    }()

    private var mainPanelWidth: CGFloat {
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

    private var mainPanelCard: some View {
        mainPanel
            .frame(width: mainPanelWidth, height: panelHeight)
            .background(.thickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                HStack(spacing: 0) {
                    resizeHandle(.leading)
                    Spacer(minLength: 0)
                    resizeHandle(.trailing)
                }
            }
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            globalActions
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.sortedStatuses) { profile in
                        profileCard(profile)
                    }
                }
            }
            footer
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            LeverSwitchIcon(
                hasReadyModels: store.displayedReadyProfiles > 0,
                hasRunningModels: store.displayedRunningProfiles > 0,
                size: 34
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(features.appDisplayName)
                    .font(.title2.bold())
                HStack(spacing: 10) {
                    Label("\(store.displayedReadyProfiles)/\(store.summary.totalProfiles) ready", systemImage: "bolt.fill")
                    Label("local control", systemImage: "switch.2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if features.supportsBenchmarks {
                    HStack(spacing: 6) {
                        utilizationBadge(label: "CPU", value: systemMetrics.cpuUsagePercent)
                        utilizationBadge(label: "RAM", value: systemMetrics.memoryUsagePercent)
                        utilizationBadge(label: "GPU", value: systemMetrics.gpuUsagePercent)
                    }
                }

                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var globalActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                actionButton("Refresh", icon: "arrow.clockwise", isBusy: store.isRefreshing) {
                    Task { await store.refresh() }
                }
                actionButton("Stop All", icon: "stop.fill", role: .destructive, isBusy: store.pendingGlobalActions.contains("stop-all")) {
                    Task { await store.stopAll() }
                }
            }

            if features.supportsBenchmarks {
                HStack {
                    actionButton(
                        "Benchmark All",
                        icon: "gauge.with.dots.needle.50percent",
                        isDisabled: store.pendingGlobalActions.contains("stop-all")
                    ) {
                        setInspectorPanel(.benchmarks)
                        Task { await store.quickBenchmark() }
                    }

                    actionButton(
                        "Reopen Last",
                        icon: "arrow.clockwise.circle",
                        isBusy: store.pendingGlobalActions.contains("reopen-last"),
                        isDisabled: !store.canReopenLastActive || store.pendingGlobalActions.contains("stop-all")
                    ) {
                        Task { await store.reopenLastActive() }
                    }
                }
            }

            if features.supportsIntegrations, !store.integrations.isEmpty {
                integrationActions
            }
        }
    }

    private var integrationActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional Integrations")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(store.integrations) { integration in
                HStack {
                    if integration.capabilities.contains("sync") {
                        actionButton(
                            integration.syncLabel ?? "Sync \(integration.displayName)",
                            icon: "arrow.triangle.2.circlepath",
                            isBusy: store.pendingIntegrationActions.contains(integration.id)
                        ) {
                            Task { await store.runIntegration(integration) }
                        }
                    }
                }
                if let description = integration.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func profileCard(_ profile: ModelProfileStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.headline)
                    Text(store.pendingLabel(for: profile.profile) ?? profile.stateDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(profile.baseURL)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                statusBadge(profile)
            }
            HStack {
                actionButton("Activate", icon: "play.circle.fill", isBusy: store.pendingLabel(for: profile.profile) == "ACTIVATING", isDisabled: store.isBusy(profile: profile.profile)) {
                    Task { await store.activate(profile.profile) }
                }
                actionButton("Start", icon: "play.fill", isBusy: store.pendingLabel(for: profile.profile) == "STARTING", isDisabled: store.isBusy(profile: profile.profile)) {
                    Task { await store.start(profile.profile) }
                }
                actionButton("Stop", icon: "stop.fill", role: .destructive, isBusy: store.pendingLabel(for: profile.profile) == "STOPPING", isDisabled: store.isBusy(profile: profile.profile)) {
                    Task { await store.stop(profile.profile) }
                }
            }
            HStack {
                actionButton("Restart", icon: "arrow.clockwise", isBusy: store.pendingLabel(for: profile.profile) == "RESTARTING", isDisabled: store.isBusy(profile: profile.profile)) {
                    Task { await store.restart(profile.profile) }
                }
                if features.supportsBenchmarks {
                    actionButton(
                        "Benchmark",
                        icon: "chart.xyaxis.line",
                        isDisabled: store.pendingGlobalActions.contains("stop-all") || store.isBusy(profile: profile.profile)
                    ) {
                        setInspectorPanel(.benchmarks)
                        Task { await store.quickBenchmark([profile.profile]) }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusBadge(_ profile: ModelProfileStatus) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tuple: (String, Color) = switch store.profileBadgeState(for: profile, relativeTo: context.date) {
            case .pending(let pending):
                (pending, .orange)
            case .running:
                ("RUNNING", .green)
            case .stale:
                ("STALE", .orange)
            case .notRunning:
                ("NOT RUNNING", .red)
            }

            Text(tuple.0)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tuple.1.opacity(0.18), in: Capsule())
                .foregroundStyle(tuple.1)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerToggleButton("Settings", panel: .settings, icon: "slider.horizontal.3")
            footerSeparator()
            footerToggleButton("Help", panel: .help, icon: "questionmark.circle")
            if features.supportsBenchmarks {
                footerSeparator()
                footerIconToggleButton("Benchmarks", panel: .benchmarks, icon: "chart.xyaxis.line")
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    if let footerState = footerState(relativeTo: context.date) {
                        Text(footerState.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(footerState.color.opacity(0.16), in: Capsule())
                            .foregroundStyle(footerState.color)
                    }
                    Text(Self.clockFormatter.string(from: context.date))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func footerSeparator() -> some View {
        Text("|")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func resizeHandle(_ edge: DashboardResizeEdge) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: DashboardResizeGeometry.edgeHitWidth)
            .contentShape(Rectangle())
            .gesture(resizeGesture(edge))
            .help("Resize dashboard")
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func resizeGesture(_ edge: DashboardResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard let hostWindow else { return }
                let startFrame = activeResizeStartFrame ?? hostWindow.frame
                if activeResizeStartFrame == nil {
                    activeResizeStartFrame = startFrame
                }
                let nextFrame = DashboardResizeGeometry.resizedFrame(
                    from: startFrame,
                    edge: edge,
                    translationX: value.translation.width,
                    minWidth: minMainPanelWidth,
                    maxWidth: maxMainPanelWidth
                )
                hostWindow.setFrame(nextFrame, display: true)
                let nextWidth = Double(nextFrame.width)
                if abs(storedMainPanelWidth - nextWidth) > 0.5 {
                    storedMainPanelWidth = nextWidth
                }
                synchronizeInspectorWindow()
            }
            .onEnded { _ in
                activeResizeStartFrame = nil
                synchronizeInspectorWindow()
            }
    }

    private func utilizationBadge(label: String, value: Double?) -> some View {
        let text: String
        if let value {
            text = "\(label) \(Int(value.rounded()))%"
        } else {
            text = "\(label) --"
        }

        return Text(text)
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.42), in: Capsule())
            .foregroundStyle(.secondary)
            .help(label == "GPU" && value == nil ? "GPU percentage unavailable on this macOS API path." : "")
    }

    private func inspectorCard(_ panel: InspectorPanel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(panel.title)
                    .font(.headline)
                Spacer()
                Button {
                    inspectorCoordinator.requestDeferredClose(of: panel)
                    // Close on next run-loop tick to avoid menu-level outside-click dismissal.
                    DispatchQueue.main.async {
                        let nextPanel = inspectorCoordinator.commitDeferredClose(of: panel)
                        synchronizeInspectorWindow(panel: nextPanel, refocusHostWindowOnHide: nextPanel == nil)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close \(panel.title)")
            }

            inspectorView(panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(width: inspectorPanelWidth, height: panelHeight, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func inspectorView(_ panel: InspectorPanel) -> some View {
        switch panel {
        case .settings:
            SettingsView(
                controllerBaseURL: $controllerBaseURL,
                profilesDirectory: store.profilesDirectory,
                controllerRoot: store.resolvedControllerRoot,
                doctorReport: store.doctorReport,
                profileDiagnostics: store.diagnosticsNeedingAttention,
                isRunningControllerDoctor: store.isRunningControllerDoctor,
                launchAtLoginManager: launchAtLoginManager,
                openProfilesDirectory: store.openProfilesDirectory,
                openControllerRoot: store.openControllerRoot,
                runControllerDoctor: {
                    Task { await store.refreshDoctorReport() }
                },
                reconnect: reconnect
            )
        case .benchmarks:
            BenchmarksPanelView(
                benchmark: store.benchmark,
                activeBenchmarkProfiles: store.activeBenchmarkProfiles,
                cooldownEndsAt: store.benchmarkCooldownEndsAt,
                runBenchmark: {
                    Task { await store.quickBenchmark() }
                }
            )
        case .help:
            HelpView(
                exampleProfilesDirectory: store.resolvedExampleProfilesDirectory,
                openExampleProfilesDirectory: store.openExampleProfilesDirectory
            )
        }
    }

    private func footerToggleButton(_ title: String, panel: InspectorPanel, icon: String) -> some View {
        Button {
            let nextPanel = inspectorCoordinator.toggle(panel)
            synchronizeInspectorWindow(panel: nextPanel)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }

    private func footerIconToggleButton(_ title: String, panel: InspectorPanel, icon: String) -> some View {
        Button {
            let nextPanel = inspectorCoordinator.toggle(panel)
            synchronizeInspectorWindow(panel: nextPanel)
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .help(title)
    }

    private func setInspectorPanel(_ nextPanel: InspectorPanel?) {
        if nextPanel == inspectorCoordinator.openPanel,
            inspectorCoordinator.deferredClosePanel != nextPanel {
            return
        }
        _ = withAnimation(inspectorAnimation) {
            inspectorCoordinator.show(nextPanel)
        }
        synchronizeInspectorWindow(panel: nextPanel)
    }

    private func synchronizeInspectorWindow(
        panel: InspectorPanel? = nil,
        refocusHostWindowOnHide: Bool = false
    ) {
        guard let hostWindow else { return }
        let currentPanel = panel ?? inspectorCoordinator.openPanel
        guard let currentPanel else {
            inspectorController.hide {
                if refocusHostWindowOnHide {
                    hostWindow.makeKeyAndOrderFront(nil)
                }
            }
            return
        }

        inspectorController.show(
            title: currentPanel.title,
            parent: hostWindow,
            width: inspectorPanelWidth,
            height: panelHeight,
            gap: panelGap,
            content: AnyView(inspectorCard(currentPanel))
        )
    }

    private func actionButton(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        isBusy: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Group {
                if isBusy {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(title)
                    }
                } else {
                    Label(title, systemImage: icon)
                        .labelStyle(.titleAndIcon)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isBusy || isDisabled)
        .accessibilityLabel(title)
    }

    private func footerState(relativeTo now: Date) -> (label: String, color: Color)? {
        switch store.statusFreshness(relativeTo: now) {
        case .cached:
            return ("CACHED", .orange)
        case .stale:
            return ("STALE", .orange)
        case .error:
            return ("ERROR", .red)
        case .fresh:
            return nil
        }
    }

    private func clampPanelWidth(_ value: Double) -> Double {
        min(max(value, minMainPanelWidth), maxMainPanelWidth)
    }

    private func configureHostWindow(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.showsResizeIndicator = true
        window.minSize = NSSize(width: minMainPanelWidth, height: panelHeight)
        window.maxSize = NSSize(width: maxMainPanelWidth, height: panelHeight)
        window.resizeIncrements = NSSize(width: 1, height: 1)
    }
}

enum DashboardResizeEdge {
    case leading
    case trailing
}

struct DashboardResizeGeometry {
    static let edgeHitWidth: CGFloat = 10

    static func resizedFrame(
        from startFrame: NSRect,
        edge: DashboardResizeEdge,
        translationX: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat
    ) -> NSRect {
        let rawWidth = switch edge {
        case .leading:
            startFrame.width - translationX
        case .trailing:
            startFrame.width + translationX
        }
        let nextWidth = min(max(rawWidth, minWidth), maxWidth)
        var frame = startFrame
        frame.size.width = nextWidth
        if edge == .leading {
            frame.origin.x = startFrame.maxX - nextWidth
        }
        return frame
    }
}
