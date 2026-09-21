import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
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

    func heroCard(_ profile: ModelProfileStatus) -> some View {
        ActiveProfileHeroView(
            profile: profile,
            store: store,
            context: .local,
            decodeTokensPerSecond: decodeTokensPerSecond(for: profile.profile),
            ttftMilliseconds: ttftMilliseconds(for: profile.profile),
            onOpenBenchmarks: { setInspectorPanel(.benchmarks) },
            theme: theme,
            accent: accent
        )
    }
}
