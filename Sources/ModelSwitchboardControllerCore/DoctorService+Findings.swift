import Foundation
import ModelSwitchboardCore

extension DoctorService {
  func appendProfileFindings(
    _ profile: ControllerProfile,
    current: ModelProfileStatus,
    result: (errors: [String], warnings: [String]),
    diagnostics: inout [ProfileDiagnostic],
    findings: inout [DoctorFinding]
  ) {
    // L12: the diagnostic is a role-flagged view over the shared
    // ModelProfileStatus snapshot (same type the status endpoint serves);
    // doctor adds only errors/warnings. The 10-field twin is deleted.
    diagnostics.append(
      ProfileDiagnostic(status: current, errors: result.errors, warnings: result.warnings))
    findings += result.errors.enumerated().map { index, message in
      DoctorFinding(
        id: "profile-\\(profile.name)-error-\\(index + 1)", severity: .p1, subsystem: "profiles",
        message: message, evidence: profile.name, remediation: remediation(for: message)
      )
    }
    findings += result.warnings.enumerated().map { index, message in
      DoctorFinding(
        id: "profile-\\(profile.name)-warning-\\(index + 1)", severity: .p2, subsystem: "profiles",
        message: message, evidence: profile.name, remediation: remediation(for: message)
      )
    }
  }
}
