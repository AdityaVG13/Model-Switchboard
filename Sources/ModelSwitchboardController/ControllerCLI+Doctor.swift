import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
  static func runDoctor(_ arguments: [String], command: String, service: ControllerService) throws {
    if command == "health" || arguments.contains("health") {
      try printJSONObject(service.doctor.healthPayload())
      return
    }
    if arguments.contains("capabilities") {
      try printJSONObject(service.doctor.capabilities())
      return
    }
    if arguments.contains("robot-docs") {
      print(
        "Use doctor, doctor health, doctor capabilities, doctor explain <id>, doctor --fix --dry-run, and doctor undo <run-id>."
      )
      return
    }
    if let topic = value(after: "explain", in: arguments) {
      try printJSONObject(service.doctor.explain(topic))
      return
    }
    if let runID = value(after: "undo", in: arguments) {
      try printJSONObject(service.doctor.undo(runID))
      return
    }
    if arguments.contains("--fix") {
      try printJSONObject(
        service.doctor.applyFixes(
          dryRun: isDryRun(arguments),
          runID: option("--run-id", in: arguments)))
      return
    }
    try printJSON(service.doctor.report())
  }
}
