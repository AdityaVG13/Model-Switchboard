import AppKit
import SwiftUI
import ModelSwitchboardCore

/// Shared list-row chrome for local and remote profiles.
struct ProfileListRowView: View {
    let profile: ModelProfileStatus
    let store: SwitchboardStore
    var hostMetrics: HostMetricsPayload? = nil
    /// Mac-reachable endpoint (SSH forward / direct rewrite). Nil hides the
    /// extra endpoint line and disables Copy when `showReachability` is true.
    var reachableEndpointURL: String? = nil
    var showReachability: Bool = false
    var endpointUnavailableHint: String? = nil
    /// When set, Benchmark menu item is labeled for that gateway.
    var gatewayDisplayName: String? = nil
    var onOpenBenchmarks: (() -> Void)? = nil
    let theme: DashboardTheme
    let accent: Color
    @AppStorage(DisplayPrivacy.defaultsKey) var hideHostInfo = false

    var isDisplayedRunning: Bool {
        MenuBarContentView.isDisplayedRunning(profile, in: store)
    }

    var pending: String? {
        store.pendingLabel(for: profile.profile)
    }

    var isBusy: Bool { pending != nil }
}
