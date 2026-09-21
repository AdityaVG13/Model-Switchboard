import Foundation
import ModelSwitchboardCore

extension ControllerService {
    public func switchProfile(_ name: String) throws {
        try withMutationLock {
            _ = try requireExistingProfile(name, action: "activate")
            for item in try statusPayload().statuses where item.profile != name && item.running {
                try stop(item.profile)
            }
            try start(name)
            try fileManager.createDirectory(
                at: configuration.runDirectory, withIntermediateDirectories: true)
            try "\(name)\n".write(to: configuration.activeProfileFile, atomically: true, encoding: .utf8)
        }
    }
}
