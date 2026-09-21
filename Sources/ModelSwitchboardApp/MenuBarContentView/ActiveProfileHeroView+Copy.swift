import SwiftUI
import ModelSwitchboardCore

extension ActiveProfileHeroView {
    var isBusy: Bool {
        store.isBusy(profile: profile.profile)
    }

    var statusLabel: String {
        let gatewayName: String? = if case .remote(let name) = context { name } else { nil }
        return ProfileHeroStatusCopy.label(
            lifecycle: profile.lifecycle,
            pending: store.pendingLabel(for: profile.profile),
            gatewayName: gatewayName
        )
    }

    var subtitle: String {
        ProfileHeroStatusCopy.endpointSubtitle(
            runtimeLabel: profile.runtimeLabel ?? profile.runtime,
            url: {
                switch context {
                case .local: return profile.baseURL
                case .remote: return reachableEndpointURL
                }
            }(),
            host: profile.host,
            port: profile.port,
            hidden: hideHostInfo
        )
    }
}
