import Darwin
import Foundation
import ModelSwitchboardCore

extension DoctorService {
  public func report() throws -> DoctorReport {
    let loaded = try service.profiles.load()
    let conflicts = service.profiles.conflicts(in: loaded)
    var diagnostics: [ProfileDiagnostic] = []
    var findings: [DoctorFinding] = []
    for profile in loaded.values.sorted(by: { $0.name < $1.name }) {
      appendProfileFindings(
        profile,
        current: service.status(for: profile, allowPortFallback: conflicts[profile.name] == nil),
        result: diagnose(profile, conflict: conflicts[profile.name]),
        diagnostics: &diagnostics,
        findings: &findings
      )
    }
    if !fileManager.fileExists(atPath: service.configuration.profilesDirectory.path) {
      findings.append(
        DoctorFinding(
          id: "profiles-directory-missing", severity: .p1, subsystem: "profiles",
          message: "profile directory is missing",
          evidence: service.configuration.profilesDirectory.path,
          remediation: "Create the profile directory and add at least one profile.",
          fixer: "create_profiles_directory"
        ))
    }
    return assembledReport(loaded: loaded, diagnostics: diagnostics, findings: findings)
  }
}
