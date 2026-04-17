import AppKit
import SwiftUI
import ModelSwitchboardCore

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

    private let mainPanelWidth: CGFloat = 470
    private let inspectorPanelWidth: CGFloat = 290
    private let panelHeight: CGFloat = 620
    private let panelGap: CGFloat = 10
    private let inspectorAnimation = Animation.easeInOut(duration: 0.32)

    @State private var inspectorPanel: InspectorPanel?
    @State private var hostWindow: NSWindow?
    @State private var anchoredRightEdge: CGFloat?

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone = .current
        return formatter
    }()

    var body: some View {
        HStack(spacing: inspectorPanel == nil ? 0 : panelGap) {
            if let inspectorPanel {
                inspectorCard(inspectorPanel)
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        )
                    )
            }

            mainPanelCard
        }
            .frame(width: totalWidth, height: panelHeight, alignment: .trailing)
            .background(
                WindowAccessor { window in
                    if hostWindow !== window {
                        hostWindow = window
                        if let resolvedWindow = window {
                            anchoredRightEdge = resolvedWindow.frame.maxX
                        }
                    }
                    stabilizeWindowFrame(window)
                }
            )
        .task {
            store.startAutoRefresh()
            updateMenuBarHelp(store.menuBarHelp)
            stabilizeWindowFrame(hostWindow)
        }
        .onDisappear {
            store.stopAutoRefresh()
        }
        .onChange(of: store.menuBarHelp) { _, newValue in
            updateMenuBarHelp(newValue)
        }
        .onChange(of: inspectorPanel) { _, _ in
            stabilizeWindowFrame(hostWindow)
        }
        .animation(inspectorAnimation, value: inspectorPanel)
        .animation(.snappy(duration: 0.18), value: store.pendingProfileActions)
        .animation(.snappy(duration: 0.18), value: store.pendingGlobalActions)
    }

    private var totalWidth: CGFloat {
        if inspectorPanel == nil {
            return mainPanelWidth
        }
        return mainPanelWidth + inspectorPanelWidth + panelGap
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
                    withAnimation(inspectorAnimation) {
                        inspectorPanel = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close \(panel.title)")
            }

            inspectorView(panel)

            Spacer(minLength: 0)
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
            withAnimation(inspectorAnimation) {
                inspectorPanel = inspectorPanel == panel ? nil : panel
            }
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }

    private func stabilizeWindowFrame(_ window: NSWindow?, animate: Bool = false) {
        guard let window else { return }

        let desiredWidth = totalWidth
        let desiredHeight = panelHeight
        let currentFrame = window.frame
        if anchoredRightEdge == nil || abs(currentFrame.width - mainPanelWidth) < 0.5 {
            anchoredRightEdge = currentFrame.maxX
        }

        guard abs(currentFrame.width - desiredWidth) > 0.5 || abs(currentFrame.height - desiredHeight) > 0.5 else {
            return
        }

        let rightEdge = anchoredRightEdge ?? currentFrame.maxX
        let nextFrame = NSRect(
            x: rightEdge - desiredWidth,
            y: currentFrame.minY,
            width: desiredWidth,
            height: desiredHeight
        )
        window.setFrame(nextFrame, display: true, animate: animate)
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
}
