import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func considerAutoBenchmarks() {
        guard canStartBenchmarkNow else { return }
        guard let profile = statuses.first(where: {
            $0.isBoardVisible && $0.ready && !autoBenchmarkedProfiles.contains($0.profile)
        })?.profile else {
            return
        }
        markAutoBenchmarked(profile)
        Task { await self.quickBenchmark([profile]) }
    }

    func apply(doctorReport: DoctorReport) {
        self.doctorReport = doctorReport
        profileDiagnostics = doctorReport.profiles.sorted(by: Self.compareDiagnostics)
    }

    func statusForProfile(_ profile: String) -> ModelProfileStatus? {
        statuses.first { $0.profile == profile }
    }

    func diagnosticForProfile(_ profile: String) -> ProfileDiagnostic? {
        profileDiagnostics.first { $0.profile == profile }
    }

    nonisolated static func compareDiagnostics(lhs: ProfileDiagnostic, rhs: ProfileDiagnostic) -> Bool {
        let lhsSeverity = diagnosticSeverity(lhs)
        let rhsSeverity = diagnosticSeverity(rhs)
        if lhsSeverity != rhsSeverity { return lhsSeverity > rhsSeverity }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    nonisolated static func diagnosticSeverity(_ diagnostic: ProfileDiagnostic) -> Int {
        diagnostic.errors.isEmpty ? (diagnostic.warnings.isEmpty ? 0 : 1) : 2
    }
}
