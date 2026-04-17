import AppKit
import SwiftUI
import ModelSwitchboardCore

@MainActor
private final class InspectorPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class InspectorPanelController {
    private var panelWindow: InspectorPanelWindow?
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?

    func show(
        title: String,
        parent: NSWindow,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        content: AnyView
    ) {
        let window: InspectorPanelWindow
        let host: NSHostingView<AnyView>

        if let existingWindow = panelWindow, let existingHost = hostingView {
            window = existingWindow
            host = existingHost
        } else {
            host = NSHostingView(rootView: content)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.autoresizingMask = [.width, .height]

            window = InspectorPanelWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovable = false
            window.isMovableByWindowBackground = false
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.transient, .moveToActiveSpace]

            panelWindow = window
            hostingView = host
        }

        host.rootView = content
        window.title = title
        window.setContentSize(NSSize(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        if parentWindow !== parent {
            parentWindow?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
            parentWindow = parent
        }

        let frame = NSRect(
            x: parent.frame.minX - gap - width,
            y: parent.frame.minY,
            width: width,
            height: height
        )
        window.setFrame(frame, display: true)
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                window.animator().alphaValue = 1
            }
        } else {
            window.orderFront(nil)
        }
    }

    func hide() {
        guard let window = panelWindow else { return }
        let fadeDuration: TimeInterval = 0.14
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            window.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async {
                self.parentWindow?.removeChildWindow(window)
                window.orderOut(nil)
                window.alphaValue = 1
            }
        }
    }
}

struct MenuBarContentView: View {
    private enum InspectorPanel: String, Identifiable {
        case settings
        case help

        var id: String { rawValue }

        var title: String {
            switch self {
            case .settings: "Settings"
            case .help: "Help"
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

    private let defaultMainPanelWidth: Double = 470
    private let minMainPanelWidth: Double = 390
    private let maxMainPanelWidth: Double = 620
    private let inspectorPanelWidth: CGFloat = 290
    private let panelHeight: CGFloat = 620
    private let panelGap: CGFloat = 10
    private let inspectorAnimation = Animation.easeInOut(duration: 0.2)

    @State private var inspectorPanel: InspectorPanel?
    @State private var hostWindow: NSWindow?
    @State private var inspectorController = InspectorPanelController()

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
                    let detectedWidth = clampPanelWidth(Double(window.frame.width))
                    if abs(detectedWidth - storedMainPanelWidth) > 0.5 {
                        storedMainPanelWidth = detectedWidth
                    }
                    synchronizeInspectorWindow()
                }
            )
        .task {
            store.startAutoRefresh()
            updateMenuBarHelp(store.menuBarHelp)
            synchronizeInspectorWindow()
        }
        .onDisappear {
            store.stopAutoRefresh()
            inspectorController.hide()
            inspectorPanel = nil
        }
        .onChange(of: store.menuBarHelp) { _, newValue in
            updateMenuBarHelp(newValue)
        }
        .onChange(of: storedMainPanelWidth) { _, newValue in
            let clamped = clampPanelWidth(newValue)
            if abs(clamped - newValue) > .ulpOfOne {
                storedMainPanelWidth = clamped
            }
            if let hostWindow {
                var frame = hostWindow.frame
                let nextWidth = CGFloat(clamped)
                if abs(frame.width - nextWidth) > 0.5 {
                    frame.origin.x += (frame.width - nextWidth)
                    frame.size.width = nextWidth
                    hostWindow.setFrame(frame, display: true, animate: false)
                }
            }
            synchronizeInspectorWindow()
        }
        .animation(inspectorAnimation, value: inspectorPanel)
        .animation(.snappy(duration: 0.18), value: store.pendingProfileActions)
        .animation(.snappy(duration: 0.18), value: store.pendingGlobalActions)
    }

    private var mainPanelCard: some View {
        mainPanel
            .frame(width: mainPanelWidth, height: panelHeight)
            .background(.thickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                hasReadyModels: store.summary.readyProfiles > 0,
                hasRunningModels: store.summary.runningProfiles > 0,
                size: 34
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(features.appDisplayName)
                    .font(.title2.bold())
                HStack(spacing: 10) {
                    Label("\(store.summary.readyProfiles)/\(store.summary.totalProfiles) ready", systemImage: "bolt.fill")
                    Label("local control", systemImage: "switch.2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
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
                actionButton("Open", icon: "link") { store.openEndpoint(profile) }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusBadge(_ profile: ModelProfileStatus) -> some View {
        let tuple: (String, Color) = if let pending = store.pendingLabel(for: profile.profile) {
            (pending, .orange)
        } else if profile.running {
            ("RUNNING", .green)
        } else {
            ("NOT RUNNING", .red)
        }

        return Text(tuple.0)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tuple.1.opacity(0.18), in: Capsule())
            .foregroundStyle(tuple.1)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerToggleButton("Settings", panel: .settings, icon: "slider.horizontal.3")
            footerToggleButton("Help", panel: .help, icon: "questionmark.circle")
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

    private func inspectorCard(_ panel: InspectorPanel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(panel.title)
                    .font(.headline)
                Spacer()
                Button {
                    setInspectorPanel(nil)
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
                launchAtLoginManager: launchAtLoginManager,
                openProfilesDirectory: store.openProfilesDirectory,
                openControllerRoot: store.openControllerRoot,
                reconnect: reconnect,
                features: features,
                benchmark: store.benchmark,
                openDashboard: store.openDashboard,
                openLatestBenchmark: store.openLatestBenchmark,
                menuPanelWidth: Binding(
                    get: { clampPanelWidth(storedMainPanelWidth) },
                    set: { storedMainPanelWidth = clampPanelWidth($0) }
                ),
                menuPanelWidthRange: minMainPanelWidth...maxMainPanelWidth,
                defaultMenuPanelWidth: defaultMainPanelWidth,
                runQuickBenchmarkAll: {
                    Task { await store.quickBenchmark() }
                }
            )
        case .help:
            HelpView()
        }
    }

    private func footerToggleButton(_ title: String, panel: InspectorPanel, icon: String) -> some View {
        Button {
            let nextPanel = inspectorPanel == panel ? nil : panel
            setInspectorPanel(nextPanel)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }

    private func setInspectorPanel(_ nextPanel: InspectorPanel?) {
        if nextPanel == inspectorPanel {
            return
        }
        withAnimation(inspectorAnimation) {
            inspectorPanel = nextPanel
        }
        synchronizeInspectorWindow()
    }

    private func synchronizeInspectorWindow() {
        guard let hostWindow else { return }
        guard let inspectorPanel else {
            inspectorController.hide()
            return
        }

        inspectorController.show(
            title: inspectorPanel.title,
            parent: hostWindow,
            width: inspectorPanelWidth,
            height: panelHeight,
            gap: panelGap,
            content: AnyView(inspectorCard(inspectorPanel))
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
        if let lastError = store.lastError {
            if lastError.localizedCaseInsensitiveContains("cached") {
                return ("CACHED", .orange)
            }
            return ("ERROR", .red)
        }

        guard let lastUpdated = store.lastUpdated else { return nil }
        let elapsed = max(0, Int(now.timeIntervalSince(lastUpdated)))

        if elapsed > 45 {
            return ("STALE", .orange)
        }

        return nil
    }

    private func clampPanelWidth(_ value: Double) -> Double {
        min(max(value, minMainPanelWidth), maxMainPanelWidth)
    }

    private func configureHostWindow(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.showsResizeIndicator = true
        window.minSize = NSSize(width: minMainPanelWidth, height: panelHeight)
        window.maxSize = NSSize(width: maxMainPanelWidth, height: panelHeight)
        window.resizeIncrements = NSSize(width: 10, height: 1)
    }
}
