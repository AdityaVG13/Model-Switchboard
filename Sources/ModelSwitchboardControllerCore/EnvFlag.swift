import Foundation
import ModelSwitchboardCore

enum EnvFlag {
    static func isEnabled(_ raw: String?) -> Bool {
        switch (raw ?? "").trimmed.lowercased() {
        case "1", "true", "yes": return true
        default: return false
        }
    }
}
