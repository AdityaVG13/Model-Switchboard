import Foundation
import ModelSwitchboardCore

extension ControllerService {
    public func start(_ name: String) throws {
        try withMutationLock {
            let loaded = try requireExistingProfile(name, action: "start")
            var environment = ProcessInfo.processInfo.environment
            environment["MODEL_PROFILE"] = name
            environment.merge(loaded[name]?.values ?? [:]) { _, new in new }
            environment["MODEL_SWITCHBOARD_PROFILE_LOADED"] = "1"
            environment["MODEL_SWITCHBOARD_CONTROLLER_BIN"] = controllerExecutableURL.path
            _ = try ProcessRunner.run(
                "/bin/bash",
                [configuration.startScript.path],
                environment: environment,
                currentDirectory: configuration.root
            )
        }
    }

    public func restart(_ name: String) throws {
        try withMutationLock {
            _ = try requireExistingProfile(name, action: "restart")
            try stop(name)
            try start(name)
        }
    }
}
