import Darwin
import Foundation
import ModelSwitchboardCore

extension ControllerServiceManager {
    func detachedControllerProcess(_ binary: URL) -> Process {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["serve"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        return process
    }
}
