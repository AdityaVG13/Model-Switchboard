import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func refreshDoctorReport() async {
        if isRunningControllerDoctor { return }
        isRunningControllerDoctor = true
        defer { isRunningControllerDoctor = false }

        do {
            let report = try await client.fetchDoctorReport()
            applyDoctorSuccess(report)
        } catch {
            if isBenignCancellation(error) { return }
            recordRefreshFailure(error)
        }
    }
}
