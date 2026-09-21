import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// Remote gateway sections appended below the local model list. Rendered
    /// only when remote gateways exist, so the single-gateway dashboard is
    /// visually unchanged.
    @ViewBuilder
    var remoteGatewaySections: some View {
        // Hairline only when the local list actually paints above remotes
        // (otherwise it double-divides under the filter tabs on an empty board).
        if !hub.enabledRemoteRuntimes.isEmpty, showsLocalModelList {
            theme.line
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.top, 4)
        }
        // Omit every profile already featured in an ACTIVE ON hero card so
        // multi-start gateways do not list the same models twice.
        ForEach(hub.enabledRemoteRuntimes) { runtime in
            remoteGatewaySection(for: runtime)
        }
    }
}
