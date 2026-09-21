import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func applyDoctorSuccess(_ report: DoctorReport) {
        apply(doctorReport: report)
        // Doctor success must not wipe a sticky bootstrap block or a
        // status-refresh failure banner (and must not paint "refreshed"
        // while the recovering cadence is still trying status).
        switch refreshState {
        case .blocked, .failed, .failedShowingCached, .refreshing:
            break
        default:
            refreshState = .refreshed
        }
    }
}
