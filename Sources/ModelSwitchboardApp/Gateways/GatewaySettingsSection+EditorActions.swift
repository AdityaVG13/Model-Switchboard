import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    var hasStoredToken: Bool {
        guard let id = draft?.id else { return false }
        return !hub.authToken(forGateway: id).isEmpty
    }

    var tokenFieldPrompt: String {
        if draftIsNew || !hasStoredToken || !draftToken.isEmpty {
            return "Paste token - stored in keychain"
        }
        return "••••••••  leave blank to keep saved token"
    }

    var tokenFieldHelp: String {
        if hasStoredToken, draftToken.isEmpty, !draftIsNew {
            return "A token is already saved in the keychain for this gateway. Leave blank to keep it, or paste a new one to replace it."
        }
        return "Required for Tailscale/direct agents with auth. Saved once in the keychain - you should not need to re-paste after relaunch."
    }

    func save() {
        guard let draft else { return }
        switch GatewayDraftValidation.validated(draft) {
        case .invalid(let message):
            validationMessage = message
        case .valid(let saved):
            hub.upsertGateway(saved, token: draftToken)
            closeEditor()
        }
    }
}
