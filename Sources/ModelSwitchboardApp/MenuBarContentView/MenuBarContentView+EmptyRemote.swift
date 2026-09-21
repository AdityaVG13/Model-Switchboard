import Foundation
import ModelSwitchboardCore

extension MenuBarContentView {
    static func remoteOnlyEmptyCopy(lastError: String?) -> String {
        if lastError != nil {
            return "This Mac controller is offline. Remote gateways below still work."
        }
        return "No local model profiles. Remote gateways are listed below."
    }
}
