import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewaySectionView {
    @ViewBuilder
    var profileRows: some View {
        if visibleProfiles.isEmpty {
            if connectionIssue == nil, store.sortedStatuses.isEmpty {
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
                    onOpenBenchmarks: onOpenBenchmarks,
                    theme: theme,
                    accent: accent
                )
            }
        }
    }
}
