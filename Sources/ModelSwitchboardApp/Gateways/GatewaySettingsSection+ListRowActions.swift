import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func gatewayRenameControls(_ runtime: GatewayRuntime) -> some View {
        HStack(spacing: 4) {
            Text(runtime.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.label)
                .lineLimit(1)
            Button {
                renamingGatewayID = runtime.id
                renameDraft = runtime.name
                validationMessage = nil
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietCraftPressStyle())
            .help("Rename this gateway")
            .accessibilityLabel("Rename \(runtime.name)")
        }
    }

    @ViewBuilder
    func gatewayRowActions(_ runtime: GatewayRuntime) -> some View {
        if renamingGatewayID == runtime.id {
            renameRowActions(runtime)
        } else {
            editRowActions(runtime)
        }
    }
}
