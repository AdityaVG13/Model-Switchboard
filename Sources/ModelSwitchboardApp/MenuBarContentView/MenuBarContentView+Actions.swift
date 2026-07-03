import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var globalActions: some View {
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

    var integrationActions: some View {
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

    func profileCard(_ profile: ModelProfileStatus) -> some View {
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

    func statusBadge(_ profile: ModelProfileStatus) -> some View {
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

    func actionButton(
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
