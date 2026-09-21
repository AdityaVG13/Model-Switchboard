import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func commitRename(id: String) {
        guard let trimmed = renameDraft.nonEmptyTrimmed else {
            validationMessage = "Give this gateway a name."
            return
        }
        _ = hub.renameGateway(id: id, to: trimmed)
        renamingGatewayID = nil
        renameDraft = ""
        validationMessage = nil
    }

    var addButton: some View {
        linkButton("Add Remote Gateway…", emphasized: true) {
            beginManualAdd()
        }
        .padding(SettingsChrome.rowInsets)
    }

    func beginManualAdd() {
        draft = GatewayConfig.ssh(name: "", sshHost: "")
        draftToken = ""
        draftIsNew = true
        linkCode = ""
        validationMessage = nil
    }
}
