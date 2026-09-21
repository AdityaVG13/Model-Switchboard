import Foundation
import ModelSwitchboardCore

extension DoctorService {
  func diagnose(_ profile: ControllerProfile, conflict: (String, [String])?) -> (
    errors: [String], warnings: [String]
  ) {
    var errors: [String] = []
    var warnings: [String] = []
    if let conflict {
      errors.append(
        "endpoint \(conflict.0) is also configured for \(conflict.1.joined(separator: ", "))")
    }
    guard let url = URL(string: profile.baseURL),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else {
      errors.append("base_url must use http or https")
      return (errors, warnings)
    }
    if profile.healthcheckMode == "disabled" { warnings.append("health check is disabled") }
    let managed = profile.runtimeSpec.launchMode != "external"
    if managed, profile["START_COMMAND"] == nil, modelSource(profile) == nil {
      errors.append("missing MODEL_DIR, MODEL_PATH, MODEL_FILE, MODEL_ID, or MODEL_REPO")
    }
    if managed, let executable = expectedExecutable(profile),
      !executableAvailable(executable, profile: profile)
    {
      errors.append("\(executable) not found in controller PATH")
    }
    return (errors, warnings)
  }

  func modelSource(_ profile: ControllerProfile) -> String? {
    ["MODEL_DIR", "MODEL_PATH", "MODEL_FILE", "MODEL_ID", "MODEL_REPO"].compactMap { profile[$0] }
      .first { !$0.isEmpty }
  }
}
