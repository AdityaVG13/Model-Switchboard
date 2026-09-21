import Foundation
import ModelSwitchboardCore

extension DoctorService {
  public func healthPayload() throws -> [String: Any] {
    let report = try report()
    return [
      "schema_version": report.schemaVersion ?? "1",
      "tool_version": report.toolVersion ?? toolVersion(),
      "generated_at": report.generatedAt ?? ISO8601DateFormatter().string(from: Date()),
      "finding_count": report.findings?.count ?? 0,
    ]
  }

  public func capabilities() -> [String: Any] {
    [
      "schema_version": "1",
      "contract_version": "1.0",
      "native": true,
      "commands": ["diagnose", "health", "capabilities", "explain", "fix", "undo"],
      "fixers": ["create_profiles_directory"],
    ]
  }

  public func explain(_ id: String) throws -> [String: Any] {
    guard let finding = try report().findings?.first(where: { $0.id == id }) else {
      return ["error": "finding_not_present", "finding_id": id]
    }
    return [
      "finding": try JSONSerialization.jsonObject(with: JSONSupport.data(finding)),
    ]
  }
}
