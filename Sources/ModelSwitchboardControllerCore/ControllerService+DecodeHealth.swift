import Foundation
import ModelSwitchboardCore

extension ControllerService {
    func decodeOpenAIModelIDs(stdout: String, profile: ControllerProfile) -> (ready: Bool, serverIDs: [String]) {
        guard let data = stdout.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = object["data"] as? [[String: Any]]
        else { return (false, []) }
        let ids = entries.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
        if EnvFlag.isEnabled(profile["HEALTHCHECK_ANY_ID"]) {
            return (!ids.isEmpty, ids)
        }
        let expected = profile["HEALTHCHECK_EXPECT_ID"] ?? profile.serverModelID
        return (!expected.isEmpty && ids.contains(expected), ids)
    }
}
