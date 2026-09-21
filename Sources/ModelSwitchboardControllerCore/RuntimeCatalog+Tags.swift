import Foundation
import ModelSwitchboardCore

extension RuntimeCatalog {
    public static func tags(for profile: ControllerProfile) -> [String] {
        let configured = (profile["RUNTIME_TAGS"] ?? profile["TAGS"] ?? "")
            .replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace).map {
                $0.lowercased()
            }
        var result: [String] = []
        for tag in [profile.runtime] + spec(for: profile).tags + configured where !result.contains(tag)
        {
            result.append(tag)
        }
        return result
    }
}
