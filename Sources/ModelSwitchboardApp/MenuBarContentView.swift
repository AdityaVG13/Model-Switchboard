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
    @Binding var controllerBaseURL: String
    let reconnect: () -> Void
    let updateMenuBarHelp: (String) -> Void

    @State private var inspectorPanel: InspectorPanel?

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone = .current
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            mainPanel
                .frame(width: inspectorPanel == nil ? 470 : 500, height: 620)

            if let inspectorPanel {
                Divider()
                inspectorView(inspectorPanel)
                    .frame(width: 280, height: 620)
                    .background(.regularMaterial)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task {
            store.startAutoRefresh()
            updateMenuBarHelp(store.menuBarHelp)
        }
        .onDisappear {
            store.stopAutoRefresh()
        }
        .onChange(of: store.menuBarHelp) { _, newValue in
            updateMenuBarHelp(newValue)
        }
        .animation(.snappy(duration: 0.18), value: inspectorPanel)
        .animation(.snappy(duration: 0.18), value: store.pendingProfileActions)
        .animation(.snappy(duration: 0.18), value: store.pendingGlobalActions)
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
                Text("Model Switchboard")
                    .font(.title2.bold())
                HStack(spacing: 10) {
                    Label("\(store.summary.readyProfiles)/\(store.summary.totalProfiles) ready", systemImage: "bolt.fill")
                    Label(store.benchmark?.running == true ? "benchmarking" : (store.benchmark?.latest?.suite ?? "idle"), systemImage: "speedometer")
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
                actionButton("Dashboard", icon: "safari") { store.openDashboard() }
                actionButton("Latest Bench", icon: "doc.text.magnifyingglass", isDisabled: store.benchmark?.latest?.markdownPath == nil) {
                    store.openLatestBenchmark()
                }
            }
            HStack {
                actionButton("Quick Bench All", icon: "speedometer", isBusy: store.pendingGlobalActions.contains("bench-all")) {
                    Task { await store.quickBenchmark() }
                }
                actionButton("Stop All", icon: "stop.fill", role: .destructive, isBusy: store.pendingGlobalActions.contains("stop-all")) {
                    Task { await store.stopAll() }
                }
            }
            if !store.integrations.isEmpty {
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
                actionButton("Bench", icon: "speedometer", isDisabled: store.isBusy(profile: profile.profile)) {
                    Task { await store.quickBenchmark([profile.profile]) }
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
                    Text(Self.clockFormatter.string(from: context.date))
                    if let lastUpdated = store.lastUpdated {
                        Text("•")
                        Text("Updated \(Self.clockFormatter.string(from: lastUpdated))")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private func inspectorView(_ panel: InspectorPanel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(panel.title)
                    .font(.headline)
                Spacer()
                Button {
                    inspectorPanel = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close \(panel.title)")
            }

            switch panel {
            case .settings:
                SettingsView(controllerBaseURL: $controllerBaseURL, reconnect: reconnect)
            case .help:
                HelpView()
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func footerToggleButton(_ title: String, panel: InspectorPanel, icon: String) -> some View {
        Button {
            inspectorPanel = inspectorPanel == panel ? nil : panel
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
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
}
