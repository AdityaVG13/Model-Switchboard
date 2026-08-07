import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    // MARK: - Selection helpers

    /// The model featured in the hero card: first running profile that matches
    /// the active filter (so an MLX filter never heroes a llama.cpp model).
    /// Keep a busy/pending profile mounted so Stop/Restart hold chrome and
    /// STOPPING/STARTING labels do not vanish mid-action.
    var heroProfile: ModelProfileStatus? {
        if let running = store.sortedStatuses.first(where: { isDisplayedRunning($0) && matchesFilter($0) }) {
            return running
        }
        return store.sortedStatuses.first(where: {
            store.isBusy(profile: $0.profile) && matchesFilter($0)
        })
    }

    var standbyProfiles: [ModelProfileStatus] {
        let hero = heroProfile?.profile
        return store.sortedStatuses.filter { status in
            status.profile != hero && matchesFilter(status)
        }
    }

    func matchesFilter(_ status: ModelProfileStatus) -> Bool {
        matchesFilter(status, in: store)
    }

    func isDisplayedRunning(_ status: ModelProfileStatus, relativeTo now: Date = .now) -> Bool {
        Self.isDisplayedRunning(status, in: store, relativeTo: now)
    }

    static func isDisplayedRunning(
        _ status: ModelProfileStatus,
        in store: SwitchboardStore,
        relativeTo now: Date = .now
    ) -> Bool {
        store.profileBadgeState(for: status, relativeTo: now) == .running
    }

    static func runtimeKind(_ status: ModelProfileStatus) -> ProfileFilter? {
        let haystack = ([status.runtime, status.runtimeLabel ?? ""] + (status.runtimeTags ?? []))
            .joined(separator: " ")
            .lowercased()
        if haystack.contains("llama") { return .llamaCpp }
        if haystack.contains("mlx") { return .mlx }
        return nil
    }

    func decodeTokensPerSecond(for profile: String) -> Double? {
        store.benchmark?.latest?.rows
            .filter { $0.profile == profile }
            .compactMap(\.decodeTokensPerSec)
            .max()
    }

    func runtimeName(_ status: ModelProfileStatus) -> String {
        status.runtimeLabel ?? status.runtime
    }

    // MARK: - Hero section

    @ViewBuilder
    var heroSection: some View {
        if let hero = heroProfile {
            heroCard(hero)
        } else if let remoteActive = remoteActiveSummary {
            remoteActiveCard(remoteActive)
        } else if store.canReopenLastActive, hub.displayedRunningProfiles == 0 {
            // Never claim "nothing running" while a remote gateway has models up.
            reopenCard
        }
    }

    /// First remote gateway that currently shows a running/ready model matching
    /// the active filter, for the hero strip when This Mac is idle.
    var remoteActiveSummary: (gatewayID: String, name: String, profile: ModelProfileStatus)? {
        for runtime in hub.enabledRemoteRuntimes {
            if let status = runtime.store.sortedStatuses.first(where: { status in
                MenuBarContentView.isDisplayedRunning(status, in: runtime.store)
                    && matchesFilter(status, in: runtime.store)
            }) {
                return (runtime.id, runtime.name, status)
            }
            if let busy = runtime.store.sortedStatuses.first(where: { status in
                runtime.store.isBusy(profile: status.profile)
                    && matchesFilter(status, in: runtime.store)
            }) {
                return (runtime.id, runtime.name, busy)
            }
        }
        return nil
    }

    func matchesFilter(_ status: ModelProfileStatus, in store: SwitchboardStore) -> Bool {
        switch profileFilter {
        case .all:
            true
        case .running:
            MenuBarContentView.isDisplayedRunning(status, in: store) || store.isBusy(profile: status.profile)
        case .mlx:
            Self.runtimeKind(status) == .mlx
        case .llamaCpp:
            Self.runtimeKind(status) == .llamaCpp
        }
    }

    private func remoteActiveCard(_ summary: (gatewayID: String, name: String, profile: ModelProfileStatus)) -> some View {
        let runtime = hub.enabledRemoteRuntimes.first { $0.id == summary.gatewayID }
        let remoteStore = runtime?.store ?? store
        let hostMetrics = runtime.map { hostMetricsMonitor.entry(forGatewayID: $0.id).metrics } ?? nil
        return ActiveProfileHeroView(
            profile: summary.profile,
            store: remoteStore,
            context: .remote(gatewayName: summary.name),
            hostMetrics: hostMetrics,
            reachableEndpointURL: runtime?.reachableEndpointURL(for: summary.profile),
            onOpenBenchmarks: { setInspectorPanel(.benchmarks) },
            theme: theme,
            accent: accent
        )
    }

    func heroCard(_ profile: ModelProfileStatus) -> some View {
        ActiveProfileHeroView(
            profile: profile,
            store: store,
            context: .local,
            decodeTokensPerSecond: decodeTokensPerSecond(for: profile.profile),
            onOpenBenchmarks: { setInspectorPanel(.benchmarks) },
            theme: theme,
            accent: accent
        )
    }

    var reopenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTHING RUNNING")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.faint)
            heroButton(
                "Reopen Last Active",
                disabled: store.pendingGlobalActions.contains("reopen-last") || store.pendingGlobalActions.contains("stop-all")
            ) {
                Task { await store.reopenLastActive() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 0, trailing: 10))
    }

    func heroButton(
        _ title: String,
        strong: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: strong ? .semibold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    strong ? theme.btnStrongBg : theme.btnBg,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .foregroundStyle(strong ? theme.btnStrongFg : theme.btnFg)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Model list

    /// Local standby/models block actually paints chrome (not EmptyView).
    var showsLocalModelList: Bool {
        if store.sortedStatuses.isEmpty && hub.hasRemoteGateways {
            return store.lastError != nil
        }
        let suppressLocalBlock = standbyProfiles.isEmpty && (
            heroProfile != nil
                || (hub.hasRemoteGateways && !store.sortedStatuses.isEmpty)
        )
        return !suppressLocalBlock
    }

    /// True when hero, standby, or any remote section has a filter match.
    var boardHasAnyFilterMatch: Bool {
        if heroProfile != nil || !standbyProfiles.isEmpty { return true }
        let featuredRemote = heroProfile == nil ? remoteActiveSummary : nil
        if featuredRemote != nil { return true }
        for runtime in hub.enabledRemoteRuntimes {
            let excludeID: String? = {
                guard let featuredRemote, featuredRemote.gatewayID == runtime.id else { return nil }
                return featuredRemote.profile.profile
            }()
            if runtime.store.sortedStatuses.contains(where: { status in
                if let excludeID, status.profile == excludeID { return false }
                return matchesFilter(status, in: runtime.store)
            }) {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    var modelListSection: some View {
        // Multi-gateway: if This Mac has no profiles at all, skip the empty
        // "MODELS · 0" block — remote sections already carry the list.
        // Still show a compact offline notice when the local controller failed.
        if store.sortedStatuses.isEmpty && hub.hasRemoteGateways {
            if store.lastError != nil {
                Text(localEmptyMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.sub)
                    .padding(EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 14))
                    .fixedSize(horizontal: false, vertical: true)
            } else if profileFilter != .all, !boardHasAnyFilterMatch {
                filterMissMessage
            } else {
                EmptyView()
            }
        } else {
            // Suppress zero-count standby chrome when the hero already owns the
            // only match, or remotes carry the filtered board.
            let suppressLocalBlock = !showsLocalModelList
            if !suppressLocalBlock {
                VStack(alignment: .leading, spacing: 0) {
                    DashboardSectionLabel(
                        text: heroProfile != nil ? "STANDBY · \(standbyProfiles.count)" : "MODELS · \(standbyProfiles.count)",
                        theme: theme
                    )
                    .padding(EdgeInsets(top: 6, leading: 4, bottom: 4, trailing: 4))

                    if standbyProfiles.isEmpty {
                        Text(localEmptyMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.sub)
                            .padding(EdgeInsets(top: 2, leading: 4, bottom: 8, trailing: 4))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(standbyProfiles) { profile in
                            profileRow(profile)
                        }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 10, bottom: 6, trailing: 10))
            } else if profileFilter != .all, !boardHasAnyFilterMatch {
                filterMissMessage
            }
        }
    }

    private var filterMissMessage: some View {
        Text("No models match this filter.")
            .font(.system(size: 11))
            .foregroundStyle(theme.sub)
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 14))
            .fixedSize(horizontal: false, vertical: true)
    }


    var localEmptyMessage: String {
        if !store.sortedStatuses.isEmpty {
            return "No models match this filter."
        }
        if hub.hasRemoteGateways {
            if store.lastError != nil {
                return "This Mac controller is offline. Remote gateways below still work."
            }
            return "No local model profiles. Remote gateways are listed below."
        }
        return "No model profiles reported yet. Check the controller connection in Settings."
    }

    func profileRow(_ profile: ModelProfileStatus) -> some View {
        ProfileListRowView(
            profile: profile,
            store: store,
            showReachability: false,
            onOpenBenchmarks: { setInspectorPanel(.benchmarks) },
            theme: theme,
            accent: accent
        )
    }
}

/// Hover highlight for list rows (SwiftUI has no `style-hover`; track it manually).
struct RowHoverHighlight: View {
    let color: Color
    @State private var isHovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovering ? color : .clear)
            .onHover { isHovering = $0 }
    }
}
