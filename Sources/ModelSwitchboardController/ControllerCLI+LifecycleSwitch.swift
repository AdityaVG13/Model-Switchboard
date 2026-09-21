import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
    static func runSwitch(_ command: String, arguments: [String], service: ControllerService) throws {
        guard let name = positionalValues(arguments, after: command).first else {
            throw ControllerError.usage("No profile selected")
        }
        if isDryRun(arguments) {
            try printPlan(command: "switch", profiles: [name])
            return
        }
        try service.switchProfile(name)
        try printJSON(service.actionResponse())
    }

    static func runStopAll(_ arguments: [String], service: ControllerService) throws {
        if isDryRun(arguments) {
            try printPlan(command: "stop-all", profiles: try service.profiles.load().keys.sorted())
            return
        }
        try service.stopAll()
        try printJSON(service.actionResponse())
    }
}
