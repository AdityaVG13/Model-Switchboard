import Foundation
import ModelSwitchboardCore

extension DoctorService {
    public func undo(_ runID: String) throws -> [String: Any] {
        let identifier = try sanitizedRunID(runID)
        let artifact = doctorRunsDirectory.appendingPathComponent(identifier).appendingPathComponent(
            "actions.json")
        guard let data = try? Data(contentsOf: artifact),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actions = payload["actions"] as? [[String: Any]]
        else {
            return ["error": "run_not_found", "run_id": identifier]
        }
        return ["run_id": identifier, "undone": undoAppliedProfileDirectoryActions(actions)]
    }

    func writeDoctorRun(identifier: String, actions: [[String: Any]]) throws {
        let directory = doctorRunsDirectory.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSupport.data(["run_id": identifier, "actions": actions]).write(
            to: directory.appendingPathComponent("actions.json"), options: .atomic)
    }

    func undoAppliedProfileDirectoryActions(_ actions: [[String: Any]]) -> [[String: Any]] {
        var undone: [[String: Any]] = []
        for action in actions.reversed()
        where action["action"] as? String == "create_profiles_directory"
            && action["status"] as? String == "applied"
        {
            guard let path = action["path"] as? String else { continue }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url == service.configuration.profilesDirectory.standardizedFileURL else { continue }
            if ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []).isEmpty {
                try? fileManager.removeItem(at: url)
                undone.append(action)
            }
        }
        return undone
    }
}
