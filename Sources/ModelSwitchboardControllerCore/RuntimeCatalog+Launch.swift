import Foundation
import ModelSwitchboardCore

extension RuntimeCatalog {
    static func launchMode(for profile: ControllerProfile, fallback: String) -> String {
        if profile["START_COMMAND"] != nil {
            return "command"
        }
        if let launchMode = profile["LAUNCH_MODE"]?.lowercased(),
            ["adapter", "external", "command"].contains(launchMode)
        {
            return launchMode
        }
        return fallback
    }
}
