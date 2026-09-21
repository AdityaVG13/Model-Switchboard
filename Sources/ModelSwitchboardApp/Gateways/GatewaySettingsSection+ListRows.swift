import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    var gatewayList: some View {
        ForEach(hub.remoteRuntimes) { runtime in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(runtime.settingsDotColor(dotOff: theme.dotOff))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        if renamingGatewayID == runtime.id {
                            TextField("Display name", text: $renameDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12.5, weight: .medium))
                                .onSubmit { commitRename(id: runtime.id) }
                        } else {
                            gatewayRenameControls(runtime)
                        }
                        Text(DisplayPrivacy.connectionSummary(runtime.config.endpointSummary, hidden: hideHostInfo))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.sub)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if renamingGatewayID == runtime.id, let validationMessage {
                            Text(validationMessage)
                                .font(.system(size: 10.5))
                                .foregroundStyle(DashboardTheme.stopRed)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    gatewayRowActions(runtime)
                }
                GatewayForceUpdateStatus(phase: runtime.forceUpdatePhase, theme: theme)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }
}
