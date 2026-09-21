import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @ViewBuilder
    func renameRowActions(_ runtime: GatewayRuntime) -> some View {
        linkButton("Save") { commitRename(id: runtime.id) }
        linkButton("Cancel") {
            renamingGatewayID = nil
            renameDraft = ""
        }
    }

    func editRowActions(_ runtime: GatewayRuntime) -> some View {
        Group {
            linkButton(GatewayConnectionBadge.updateActionTitle(for: runtime)) {
                Task { await hub.forceUpdateGateway(id: runtime.id) }
            }
            .disabled(runtime.forceUpdatePhase.isUpdating)
            .help(GatewayConnectionBadge.help(for: runtime))
            linkButton("Edit") {
                renamingGatewayID = nil
                draft = runtime.config
                draftToken = hub.authToken(forGateway: runtime.id)
                draftIsNew = false
                validationMessage = nil
            }
        }
    }
}
