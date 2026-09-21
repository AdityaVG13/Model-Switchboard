import Darwin
import Foundation
import ModelSwitchboardCore

extension DoctorService {
  func assembledReport(
    loaded: [String: ControllerProfile],
    diagnostics: [ProfileDiagnostic],
    findings: [DoctorFinding]
  ) -> DoctorReport {
    let integrations = service.integrationStatus()
    let plist = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/io.modelswitchboard.controller.plist")
    let launchAgentRunning =
      (try? ProcessRunner.run(
        "/bin/launchctl", ["print", "gui/\\(getuid())/io.modelswitchboard.controller"], check: false
      ).status) == 0
    return DoctorReport(
      controller: ControllerHeartbeat(
        url: "http://\(service.configuration.host):\(service.configuration.port)/api/status",
        reachable: true,
        profiles: loaded.count,
        integrations: integrations.count
      ),
      launchAgent: LaunchAgentStatus(
        plistPath: plist.path,
        installed: fileManager.fileExists(atPath: plist.path),
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
      findings: findings,
      nextSteps: findings.prefix(5).compactMap(\.remediation)
    )
  }
}
