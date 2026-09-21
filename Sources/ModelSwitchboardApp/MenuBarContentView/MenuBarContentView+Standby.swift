import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    @ViewBuilder
    var localStandbyBlock: some View {
        if showsLocalModelList {
            VStack(alignment: .leading, spacing: 0) {
                DashboardSectionLabel(
                    text: heroProfile != nil ? "STANDBY · \(standbyProfiles.count)" : "MODELS · \(standbyProfiles.count)",
                    theme: theme
                )
                .padding(EdgeInsets(top: 6, leading: 4, bottom: 4, trailing: 4))

                if standbyProfiles.isEmpty {
                    emptyCopy(localEmptyMessage, compact: true)
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
