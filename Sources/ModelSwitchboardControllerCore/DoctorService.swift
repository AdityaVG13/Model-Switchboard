import Foundation
import ModelSwitchboardCore

public final class DoctorService: @unchecked Sendable {
  private unowned let service: ControllerService
  private let fileManager = FileManager.default

  init(service: ControllerService) {
    self.service = service
  }

  public func report() throws -> DoctorReport {
    let loaded = try service.profiles.load()
    let conflicts = service.profiles.conflicts(in: loaded)
    var diagnostics: [ProfileDiagnostic] = []
    var findings: [DoctorFinding] = []
    for profile in loaded.values.sorted(by: { $0.name < $1.name }) {
      let current = service.status(for: profile, allowPortFallback: conflicts[profile.name] == nil)
      let result = diagnose(profile, conflict: conflicts[profile.name])
      diagnostics.append(
        ProfileDiagnostic(
          profile: profile.name,
          displayName: profile.displayName,
          runtime: profile.runtime,
          runtimeLabel: profile.runtimeSpec.label,
          runtimeTags: profile.runtimeTags,
          launchMode: profile.runtimeSpec.launchMode,
          errors: result.errors,
          warnings: result.warnings,
          running: current.running,
          ready: current.ready,
          pid: current.pid,
          baseURL: profile.baseURL
        ))
      findings += result.errors.enumerated().map { index, message in
        DoctorFinding(
          id: "profile-\(profile.name)-error-\(index + 1)", severity: "P1", subsystem: "profiles",
          message: message, evidence: profile.name, remediation: remediation(for: message),
          autoFixable: false
        )
      }
      findings += result.warnings.enumerated().map { index, message in
        DoctorFinding(
          id: "profile-\(profile.name)-warning-\(index + 1)", severity: "P2", subsystem: "profiles",
          message: message, evidence: profile.name, remediation: remediation(for: message),
          autoFixable: false
        )
      }
    }
    if !fileManager.fileExists(atPath: service.configuration.profilesDirectory.path) {
      findings.append(
        DoctorFinding(
          id: "profiles-directory-missing", severity: "P1", subsystem: "profiles",
          message: "profile directory is missing",
          evidence: service.configuration.profilesDirectory.path,
          remediation: "Create the profile directory and add at least one profile.",
          autoFixable: true, fixer: "create_profiles_directory"
        ))
    }
    let integrations = service.integrationStatus()
    let plist = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/io.modelswitchboard.controller.plist")
    let launchAgentRunning =
      (try? ProcessRunner.run(
        "/bin/launchctl", ["print", "gui/\(getuid())/io.modelswitchboard.controller"], check: false
      ).status) == 0
    let healthy = findings.allSatisfy { $0.severity != "P0" && $0.severity != "P1" }
    let steps = findings.prefix(5).compactMap(\.remediation)
    return DoctorReport(
      controller: ControllerHeartbeat(
        url: "http://\(service.configuration.host):\(service.configuration.port)/api/status",
        reachable: true,
        profiles: loaded.count,
        integrations: integrations.count
      ),
      launchAgent: LaunchAgentStatus(
        plistPath: plist.path,
        installed: launchAgentRunning || fileManager.fileExists(atPath: plist.path),
        running: launchAgentRunning
      ),
      integrations: integrations,
      profilesDirectory: service.configuration.profilesDirectory.path,
      controllerRoot: service.configuration.root.path,
      profiles: diagnostics,
      schemaVersion: "1",
      doctorContractVersion: "1.0",
      toolVersion: toolVersion(),
      generatedAt: ISO8601DateFormatter().string(from: Date()),
      healthy: healthy,
      findings: findings,
      nextSteps: steps
    )
  }

  public func healthPayload() throws -> [String: Any] {
    let report = try report()
    return [
      "schema_version": report.schemaVersion ?? "1",
      "tool_version": report.toolVersion ?? toolVersion(),
      "generated_at": report.generatedAt ?? ISO8601DateFormatter().string(from: Date()),
      "healthy": report.healthy ?? false,
      "finding_count": report.findings?.count ?? 0,
      "auto_fixable_count": report.findings?.filter { $0.autoFixable == true }.count ?? 0,
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
      return ["ok": false, "error": "finding_not_present", "finding_id": id]
    }
    return [
      "ok": true,
      "finding": try JSONSerialization.jsonObject(with: JSONSupport.data(finding)),
    ]
  }

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
      let directory = doctorRunsDirectory.appendingPathComponent(identifier, isDirectory: true)
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try JSONSupport.data(["run_id": identifier, "actions": actions]).write(
        to: directory.appendingPathComponent("actions.json"), options: .atomic)
    }
    return [
      "ok": true,
      "dry_run": dryRun,
      "actions_taken": missing ? 1 : 0,
      "run_id": identifier,
      "actions": actions,
    ]
  }

  public func undo(_ runID: String) throws -> [String: Any] {
    let identifier = try sanitizedRunID(runID)
    let artifact = doctorRunsDirectory.appendingPathComponent(identifier).appendingPathComponent(
      "actions.json")
    guard let data = try? Data(contentsOf: artifact),
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let actions = payload["actions"] as? [[String: Any]]
    else {
      return ["ok": false, "error": "run_not_found", "run_id": identifier]
    }
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
    return ["ok": true, "run_id": identifier, "undone": undone]
  }

  private func diagnose(_ profile: ControllerProfile, conflict: (String, [String])?) -> (
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

  private func modelSource(_ profile: ControllerProfile) -> String? {
    ["MODEL_DIR", "MODEL_PATH", "MODEL_FILE", "MODEL_ID", "MODEL_REPO"].compactMap { profile[$0] }
      .first { !$0.isEmpty }
  }

  private func expectedExecutable(_ profile: ControllerProfile) -> String? {
    switch profile.runtime {
    case "llama.cpp", "turboquant": return "llama-server"
    case "mlx": return "mlx_lm.server"
    case "vllm-mlx": return "vllm-mlx"
    case "ollama": return "ollama"
    case "vllm": return "vllm"
    case "sglang": return "python3"
    default: return nil
    }
  }

  private func executableAvailable(_ executable: String, profile: ControllerProfile) -> Bool {
    let configured = ["SERVER_BIN", "LLAMA_SERVER_BIN", "MLX_SERVER_BIN", "VLLM_MLX_BIN"]
      .compactMap { profile[$0] }.contains {
        fileManager.isExecutableFile(atPath: NSString(string: $0).expandingTildeInPath)
      }
    if configured { return true }
    return (try? ProcessRunner.run("/usr/bin/which", [executable], check: false).status) == 0
  }

  private func remediation(for message: String) -> String {
    if message.contains("also configured") { return "Assign every profile a unique host and port." }
    if message.contains("missing MODEL") { return "Configure a model source in the profile." }
    if message.contains("not found") {
      return "Install the runtime or configure its executable path."
    }
    if message.contains("health check") { return "Configure an enabled loopback health check." }
    return "Correct the profile configuration and rerun doctor."
  }

  private func toolVersion() -> String {
    let versionURL = service.configuration.root.deletingLastPathComponent().appendingPathComponent(
      "VERSION")
    return
      (try? String(contentsOf: versionURL, encoding: .utf8).trimmingCharacters(
        in: .whitespacesAndNewlines)) ?? "dev"
  }

  private var doctorRunsDirectory: URL {
    service.configuration.root.deletingLastPathComponent().appendingPathComponent(
      ".doctor/runs", isDirectory: true)
  }

  private func sanitizedRunID(_ value: String) throws -> String {
    guard value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
      throw ControllerError.usage("invalid doctor run id")
    }
    return value
  }

  private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "")
      .replacingOccurrences(of: "-", with: "")
  }
}
