import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func syncAuxiliaryStateAfterMutation() async {
        await probeLoopbackEndpointsIfNeeded()
        if let report = try? await client.fetchDoctorReport() {
            apply(doctorReport: report)
        }
    }
}
