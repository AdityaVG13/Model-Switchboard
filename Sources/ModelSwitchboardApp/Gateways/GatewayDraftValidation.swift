import Foundation
import ModelSwitchboardCore

/// Settings-form save checks. Returns the persisted config or a field error.
enum GatewayDraftValidation {
    enum Outcome {
        case valid(GatewayConfig)
        case invalid(String)
    }

    static func validated(_ draft: GatewayConfig) -> Outcome {
        let trimmedName = draft.name.whitespaceTrimmed
        if trimmedName.isEmpty {
            return .invalid("Give this gateway a name.")
        }
        switch draft.connection {
        case .ssh(var ssh):
            return validateSSH(draft: draft, ssh: &ssh, name: trimmedName)
        case .direct(var direct):
            return validateDirect(draft: draft, direct: &direct, name: trimmedName)
        }
    }
}
