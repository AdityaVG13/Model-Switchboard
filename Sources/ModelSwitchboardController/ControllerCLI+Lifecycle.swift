import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
    static func runLifecycle(_ command: String, arguments: [String], service: ControllerService) throws {
        let names = positionalValues(arguments, after: command)
        guard !names.isEmpty else { throw ControllerError.usage("No profiles selected") }
        let all = try service.profiles.load().keys.sorted()
        let selected = names == ["all"] ? all : names
        if isDryRun(arguments) {
            try printPlan(command: command, profiles: selected)
            return
        }
        for name in selected {
            try applyLifecycle(command, name: name, service: service)
        }
        try printJSON(service.actionResponse())
    }
}
