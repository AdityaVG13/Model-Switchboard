import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// Remote gateway sections appended below the local model list. Rendered
    /// only when remote gateways exist, so the single-gateway dashboard is
    /// visually unchanged.
    @ViewBuilder
    var remoteGatewaySections: some View {
        ForEach(hub.enabledRemoteRuntimes) { runtime in
            RemoteGatewaySectionView(
                runtime: runtime,
                filter: profileFilter,
                theme: theme,
                accent: accent
            )
        }
    }
}

/// One remote gateway's header plus its model rows, visually matching the
/// local standby list.
struct RemoteGatewaySectionView: View {
    @Bindable var runtime: GatewayRuntime
    let filter: MenuBarContentView.ProfileFilter
    let theme: DashboardTheme
    let accent: Color

    private var store: SwitchboardStore { runtime.store }

    private var visibleProfiles: [ModelProfileStatus] {
        store.sortedStatuses.filter { status in
            switch filter {
            case .all:
                true
            case .running:
                MenuBarContentView.isDisplayedRunning(status, in: store) || store.isBusy(profile: status.profile)
            case .mlx:
                MenuBarContentView.runtimeKind(status) == .mlx
            case .llamaCpp:
                MenuBarContentView.runtimeKind(status) == .llamaCpp
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if let issue = connectionIssue {
                Text(issue)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.pendingOrange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 4))
            }
            if visibleProfiles.isEmpty {
                if connectionIssue == nil {
                    Text(store.sortedStatuses.isEmpty
                        ? "No model profiles reported yet."
                        : "No models match this filter.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.sub)
                        .padding(EdgeInsets(top: 2, leading: 4, bottom: 8, trailing: 4))
                }
            } else {
                ForEach(visibleProfiles) { profile in
                    RemoteProfileRowView(
                        runtime: runtime,
                        profile: profile,
                        theme: theme,
                        accent: accent
                    )
                }
            }
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 6, trailing: 10))
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            DashboardSectionLabel(
                text: "\(runtime.name.uppercased()) · \(store.displayedReadyProfiles)/\(store.summary.totalProfiles) READY",
                theme: theme
            )
            Spacer(minLength: 0)
            Text(connectionBadge)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.faint)
        }
        .padding(EdgeInsets(top: 10, leading: 4, bottom: 4, trailing: 4))
    }

    private var connectionBadge: String {
        switch runtime.config.kind {
        case .direct:
            return "DIRECT"
        case .ssh:
            switch runtime.tunnelState {
            case .idle: return "SSH · OFF"
            case .connecting: return "SSH · CONNECTING"
            case .established: return "SSH · TUNNELED"
            case .failed: return "SSH · FAILED"
            }
        }
    }

    private var statusColor: Color {
        if case .failed = runtime.tunnelState { return DashboardTheme.stopRed }
        if runtime.tunnelState == .connecting { return DashboardTheme.pendingOrange }
        if store.lastError != nil { return DashboardTheme.stopRed }
        if store.displayedReadyProfiles > 0 { return DashboardTheme.runningGreen }
        return theme.dotOff
    }

    private var connectionIssue: String? {
        if case .failed(let message) = runtime.tunnelState { return message }
        return store.lastError
    }
}

/// A remote model row: same visual language as the local rows, with actions
/// bound to the gateway's own store and a copyable, locally valid endpoint.
struct RemoteProfileRowView: View {
    @Bindable var runtime: GatewayRuntime
    let profile: ModelProfileStatus
    let theme: DashboardTheme
    let accent: Color

    private var store: SwitchboardStore { runtime.store }

    var body: some View {
        let pending = store.pendingLabel(for: profile.profile)
        let isBusy = pending != nil

        HStack(spacing: 9) {
            Circle()
                .fill(dotColor(pending: pending))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle(pending: pending))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                primaryButton(pending: pending, isBusy: isBusy)
                rowMenu(isBusy: isBusy)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6))
        .contentShape(Rectangle())
        .background(RowHoverHighlight(color: theme.hoverBg))
    }

    private var isDisplayedRunning: Bool {
        MenuBarContentView.isDisplayedRunning(profile, in: store)
    }

    private func dotColor(pending: String?) -> Color {
        switch store.profileBadgeState(for: profile, relativeTo: .now) {
        case .pending:
            return DashboardTheme.pendingOrange
        case .running:
            return DashboardTheme.runningGreen
        case .stale, .notRunning:
            return theme.dotOff
        }
    }

    private func subtitle(pending: String?) -> String {
        var parts = [profile.runtimeLabel ?? profile.runtime, ":\(profile.port)"]
        if let pending {
            parts.append(pending.lowercased() + "…")
        } else if let rssMB = profile.rssMB, isDisplayedRunning {
            parts.append(String(format: "%.1f GB", rssMB / 1024))
        }
        if isDisplayedRunning, runtime.reachableEndpointURL(for: profile) == nil {
            parts.append("remote-only")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func primaryButton(pending: String?, isBusy: Bool) -> some View {
        if isBusy {
            iconContainer {
                ProgressView()
                    .controlSize(.mini)
            }
        } else if isDisplayedRunning {
            actionIcon("stop.fill", color: DashboardTheme.stopRed, label: "Stop \(profile.displayName)") {
                Task { await store.stop(profile.profile) }
            }
        } else {
            actionIcon("play.fill", color: accent, label: "Activate \(profile.displayName)") {
                Task { await store.activate(profile.profile) }
            }
        }
    }

    private func rowMenu(isBusy: Bool) -> some View {
        let endpointURL = runtime.reachableEndpointURL(for: profile)
        return Menu {
            Button("Start (keep others running)") {
                Task { await store.start(profile.profile) }
            }
            .disabled(isBusy || profile.running)
            Button("Restart") {
                Task { await store.restart(profile.profile) }
            }
            .disabled(isBusy)
            Divider()
            if let endpointURL {
                Button("Copy Endpoint URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(endpointURL, forType: .string)
                }
            } else {
                Button("Endpoint not reachable from this Mac") {}
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.sub)
                .frame(width: 26, height: 26)
                .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More actions for \(profile.displayName)")
    }

    private func actionIcon(
        _ systemName: String, color: Color, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconContainer {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func iconContainer(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: 26, height: 26)
            .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
    }
}
