import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    var rowAccessibilityLabel: String {
        if let endpointLine {
            return "\(profile.displayName), \(subtitle), \(endpointLine)"
        }
        return "\(profile.displayName), \(subtitle)"
    }

    /// `<served model id> · <URL usable from this Mac>` for live remote rows.
    var endpointLine: String? {
        guard showReachability, isDisplayedRunning, profile.ready else { return nil }
        let servedModel = profile.serverIDs.first ?? profile.serverModelID
        guard let url = reachableEndpointURL else {
            let why = endpointUnavailableHint ?? "not reachable from this Mac"
            return "\(servedModel) · \(DisplayPrivacy.hostPort(profile.host, port: profile.port, hidden: hideHostInfo)) (\(why))"
        }
        return "\(servedModel) · \(DisplayPrivacy.url(url, hidden: hideHostInfo))"
    }
}
