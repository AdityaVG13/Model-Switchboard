import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var headerFilterTabs: some View {
        DashboardSegmentedTabs(
            options: visibleFilterChips.map(\.id),
            label: { id in visibleFilterChips.first(where: { $0.id == id })?.label ?? id },
            selection: $profileFilter,
            theme: theme
        )
        .onAppear {
            if !visibleFilterChips.contains(where: { $0.id == profileFilter }) {
                profileFilter = DashboardFilterChip.all.id
            }
        }
        .onChange(of: filterChipsRaw) { _, _ in
            if !visibleFilterChips.contains(where: { $0.id == profileFilter }) {
                profileFilter = DashboardFilterChip.all.id
            }
        }
    }
}
