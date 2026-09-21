import Darwin
import Foundation
import ModelSwitchboardCore
import ServiceManagement

extension ControllerServiceManager {
    func waitForController(timeoutSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await Self.offMainQueue { Self.controllerReachableSync() } { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
