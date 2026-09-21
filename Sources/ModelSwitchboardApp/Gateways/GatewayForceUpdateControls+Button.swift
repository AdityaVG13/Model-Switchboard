import SwiftUI
import ModelSwitchboardCore

extension GatewayForceUpdateControls {
    var updateButton: some View {
        Button(action: onUpdate) {
            Text(GatewayConnectionBadge.updateActionTitle(for: runtime, agentStale: agentStale))
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(
                    GatewayConnectionBadge.updateActionColor(
                        for: runtime,
                        agentStale: agentStale,
                        theme: theme,
                        accent: accent
                    )
                )
                .padding(.horizontal, capsuleUpdate ? 6 : 0)
                .padding(.vertical, capsuleUpdate ? 3 : 0)
                .background {
                    if capsuleUpdate {
                        Capsule().fill(theme.btnBg.opacity(0.85))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .disabled(runtime.forceUpdatePhase.isUpdating)
        .help(GatewayConnectionBadge.help(
            for: runtime,
            agentStale: agentStale,
            remoteVersion: remoteVersion
        ))
        .accessibilityLabel("Update " + runtime.name)
        .accessibilityHint(GatewayConnectionBadge.help(
            for: runtime,
            agentStale: agentStale,
            remoteVersion: remoteVersion
        ))
    }
}
