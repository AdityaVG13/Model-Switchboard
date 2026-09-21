import SwiftUI
import ModelSwitchboardCore

extension GatewayForceUpdateControls {
    var statusLabel: some View {
        Text(GatewayConnectionBadge.statusText(for: runtime))
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(theme.faint)
            .accessibilityLabel(GatewayConnectionBadge.statusText(for: runtime))
    }
}
