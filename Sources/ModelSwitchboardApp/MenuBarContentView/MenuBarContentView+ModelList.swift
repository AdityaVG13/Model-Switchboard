import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    // MARK: - Selection helpers

    /// Local models featured as ACTIVE heroes: every running (or busy) profile
    /// that matches the active filter. Multi-start gateways can show several.
    var localHeroProfiles: [ModelProfileStatus] {
        store.sortedStatuses.filter { status in
            matchesFilter(status)
                && (isDisplayedRunning(status) || store.isBusy(profile: status.profile))
        }
    }

    /// Back-compat alias for call sites that still ask for "the" hero.
    var heroProfile: ModelProfileStatus? { localHeroProfiles.first }

    var localHeroProfileIDs: Set<String> {
        Set(localHeroProfiles.map(\.profile))
    }

    var standbyProfiles: [ModelProfileStatus] {
        let heroes = localHeroProfileIDs
        return store.sortedStatuses.filter { status in
            !heroes.contains(status.profile) && matchesFilter(status)
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

    /// Legacy mlx / llama.cpp classification for tests and older call sites.
    static func runtimeKind(_ status: ModelProfileStatus) -> String? {
        DashboardFilterPreferences.legacyRuntimeKind(status)
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
        let localHeroes = localHeroProfiles
        let remotes = remoteHeroSummaries
        if !localHeroes.isEmpty || !remotes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(localHeroes) { hero in
                    heroCard(hero)
                }
                ForEach(remotes, id: \.rowID) { summary in
                    remoteActiveCard(summary)
                }
            }
        } else if store.canReopenLastActive, hub.displayedRunningProfiles == 0 {
            // Never claim "nothing running" while a remote gateway has models up.
            reopenCard
        }
    }

    /// Every remote running/busy profile matching the filter, for ACTIVE ON … cards.
    /// When This Mac already has local heroes, remotes still get their own cards.
    struct RemoteHeroSummary: Identifiable {
        var id: String { rowID }
        let rowID: String
        let gatewayID: String
        let name: String
        let profile: ModelProfileStatus
    }

    var remoteHeroSummaries: [RemoteHeroSummary] {
        var out: [RemoteHeroSummary] = []
        for runtime in hub.enabledRemoteRuntimes {
            for status in runtime.store.sortedStatuses {
                let running = MenuBarContentView.isDisplayedRunning(status, in: runtime.store)
                let busy = runtime.store.isBusy(profile: status.profile)
                guard running || busy else { continue }
                guard matchesFilter(status, in: runtime.store) else { continue }
                out.append(
                    RemoteHeroSummary(
                        rowID: "\(runtime.id)::\(status.profile)",
                        gatewayID: runtime.id,
                        name: runtime.name,
                        profile: status
                    )
                )
            }
        }
        return out
    }

    /// First remote hero (compat for older helpers).
    var remoteActiveSummary: RemoteHeroSummary? {
        remoteHeroSummaries.first
    }

    /// Profile ids already featured as remote ACTIVE heroes, keyed by gateway.
    var remoteHeroProfileIDsByGateway: [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for summary in remoteHeroSummaries {
            map[summary.gatewayID, default: []].insert(summary.profile.profile)
        }
        return map
    }

    func matchesFilter(_ status: ModelProfileStatus, in store: SwitchboardStore) -> Bool {
        DashboardFilterPreferences.matches(
            status,
            filterID: profileFilter,
            isDisplayedRunning: MenuBarContentView.isDisplayedRunning(status, in: store),
            isBusy: store.isBusy(profile: status.profile)
        )
    }

    private func remoteActiveCard(_ summary: RemoteHeroSummary) -> some View {
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
        if !localHeroProfiles.isEmpty || !standbyProfiles.isEmpty { return true }
        if !remoteHeroSummaries.isEmpty { return true }
        let excluded = remoteHeroProfileIDsByGateway
        for runtime in hub.enabledRemoteRuntimes {
            let excludeIDs = excluded[runtime.id] ?? []
            if runtime.store.sortedStatuses.contains(where: { status in
                if excludeIDs.contains(status.profile) { return false }
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
            } else if profileFilter != DashboardFilterChip.all.id, !boardHasAnyFilterMatch {
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
            } else if profileFilter != DashboardFilterChip.all.id, !boardHasAnyFilterMatch {
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
