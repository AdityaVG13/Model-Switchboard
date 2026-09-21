import Foundation
import ModelSwitchboardCore

extension DoctorService {
    public func applyFixes(dryRun: Bool, runID: String? = nil) throws -> [String: Any] {
        let missing = !fileManager.fileExists(atPath: service.configuration.profilesDirectory.path)
        if missing, !dryRun {
            try fileManager.createDirectory(
                at: service.configuration.profilesDirectory, withIntermediateDirectories: true)
        }
        let identifier = try sanitizedRunID(runID ?? "doctor-\(timestamp())")
        let actions: [[String: Any]] =
            missing
            ? [
                [
                    "action": "create_profiles_directory",
                    "path": service.configuration.profilesDirectory.path,
                    "status": dryRun ? "planned" : "applied",
                ]
            ] : []
        if !dryRun {
            try writeDoctorRun(identifier: identifier, actions: actions)
        }
        return [
            "dry_run": dryRun,
            "actions_taken": missing ? 1 : 0,
            "run_id": identifier,
            "actions": actions,
        ]
    }
}
