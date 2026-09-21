import SwiftUI
import ModelSwitchboardCore


enum ProfileHeroStatusCopy {
    /// Board/hero status line. Switches the named lifecycle, not the wire
    /// booleans: stopped is STOPPED, not STARTING.
    static func label(
        lifecycle: ModelProfileStatus.Lifecycle,
        pending: String?,
        gatewayName: String?
    ) -> String {
        let core: String = {
            if let pending { return pending.uppercased() }
            switch lifecycle {
            case .running, .readyUnowned: return "ACTIVE"
            case .starting: return "WARMING"
            case .stopped: return "STOPPED"
            }
        }()
        if let gatewayName {
            return "\(core) ON \(gatewayName.uppercased())"
        }
        return core
    }

    /// Runtime + reachable endpoint, with the same host mask as list rows.
    static func endpointSubtitle(
        runtimeLabel: String,
        url: String?,
        host: String,
        port: String,
        hidden: Bool
    ) -> String {
        let endpoint: String
        if let url, !url.isEmpty {
            endpoint = DisplayPrivacy.url(url, hidden: hidden)
        } else {
            endpoint = DisplayPrivacy.hostPort(host, port: port, hidden: hidden)
        }
        return "\(runtimeLabel) · \(endpoint)"
    }
}
