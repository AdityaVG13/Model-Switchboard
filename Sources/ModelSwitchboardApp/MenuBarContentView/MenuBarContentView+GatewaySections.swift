import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// Remote gateway sections appended below the local model list. Rendered
    /// only when remote gateways exist, so the single-gateway dashboard is
    /// visually unchanged.
    @ViewBuilder
    var remoteGatewaySections: some View {
        // Hairline only when local content sits above remotes (otherwise it
        // double-divides under the filter tabs).
        if !hub.enabledRemoteRuntimes.isEmpty, !store.sortedStatuses.isEmpty {
            theme.line
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.top, 4)
        }
        // When This Mac has no local hero, the first remote ready model is
        // featured in the ACTIVE ON … card — omit that same profile from the
        // gateway list so it does not appear twice.
        let featuredRemote = heroProfile == nil ? remoteActiveSummary : nil
        ForEach(hub.enabledRemoteRuntimes) { runtime in
            let excludeProfile: String? = {
                guard let featuredRemote, featuredRemote.gatewayID == runtime.id else { return nil }
                return featuredRemote.profile.profile
            }()
            RemoteGatewaySectionView(
                runtime: runtime,
                filter: profileFilter,
                excludeProfileID: excludeProfile,
                hostMetrics: hostMetricsMonitor.entry(forGatewayID: runtime.id).metrics,
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
    /// Profile id already shown in the hero ACTIVE ON … card (if any).
    var excludeProfileID: String? = nil
    /// Live host metrics from GET /api/host/metrics (GPU/VRAM), not process RSS.
    var hostMetrics: HostMetricsPayload? = nil
    let theme: DashboardTheme
    let accent: Color

    private var store: SwitchboardStore { runtime.store }

    private var visibleProfiles: [ModelProfileStatus] {
        store.sortedStatuses.filter { status in
            if let excludeProfileID, status.profile == excludeProfileID {
                return false
            }
            switch filter {
            case .all:
                return true
            case .running:
                return MenuBarContentView.isDisplayedRunning(status, in: store) || store.isBusy(profile: status.profile)
            case .mlx:
                return MenuBarContentView.runtimeKind(status) == .mlx
            case .llamaCpp:
                return MenuBarContentView.runtimeKind(status) == .llamaCpp
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
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 4))
            }
            if visibleProfiles.isEmpty {
                if connectionIssue == nil {
                    Text(emptyProfilesMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(EdgeInsets(top: 2, leading: 4, bottom: 8, trailing: 4))
                }
            } else {
                ForEach(visibleProfiles) { profile in
                    ProfileListRowView(
                        profile: profile,
                        store: store,
                        hostMetrics: hostMetrics,
                        reachableEndpointURL: runtime.reachableEndpointURL(for: profile),
                        showReachability: true,
                        endpointUnavailableHint: runtime.config.kind == .ssh
                            ? "not forwarded to this Mac"
                            : "bound on host only",
                        gatewayDisplayName: runtime.name,
                        theme: theme,
                        accent: accent
                    )
                }
            }
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 6, trailing: 10))
    }

    private var emptyProfilesMessage: String {
        if !store.sortedStatuses.isEmpty {
            return "No models match this filter."
        }
        if let profilesDirectory = store.profilesDirectory, !profilesDirectory.isEmpty {
            return "No model profiles in \(profilesDirectory). Drop .env/.json launch files there, or re-run `model-switchboard-agent link` on the host to pick another folder."
        }
        return "No model profiles reported yet. On the host, run `model-switchboard-agent link` to choose a profiles folder."
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
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
            if let chip = HostMetricsPresentation.sectionMetricsChip(hostMetrics) {
                Text(chip)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.9))
                    .lineLimit(1)
                    .padding(.leading, 12)
                    .accessibilityLabel("Host GPU metrics: \(chip)")
            }
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
        // Fresh contact with the agent counts as online even with 0 models ready.
        if store.lastUpdated != nil, store.statusFreshness(relativeTo: .now) == .fresh {
            return DashboardTheme.runningGreen.opacity(0.55)
        }
        return theme.dotOff
    }

    private var connectionIssue: String? {
        if case .failed(let message) = runtime.tunnelState { return message }
        return store.lastError
    }
}
