import Foundation
import ModelSwitchboardCore
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
  static func execute(
    _ command: String,
    arguments: [String],
    service: ControllerService,
    configuration: ControllerConfiguration
  ) throws {
    switch command {
    case "serve", "serve-web":
      try runServe(service: service, configuration: configuration)
    case "status":
      try runStatus(arguments, service: service)
    case "list":
      try runList(service: service)
    case "start", "stop", "restart":
      try runLifecycle(command, arguments: arguments, service: service)
    case "switch", "activate":
      try runSwitch(command, arguments: arguments, service: service)
    case "stop-all":
      try runStopAll(arguments, service: service)
    case "integrations":
      try runIntegrations(service: service)
    case "run-integration":
      try runIntegration(arguments, service: service)
    case "doctor", "diagnose", "health":
      try runDoctor(arguments, command: command, service: service)
    case "triage":
      try runTriage(service: service)
    case "capabilities":
      try runCapabilities()
    case "robot-docs", "docs":
      runRobotDocs()
    case "benchmark":
      try runBenchmark(arguments, service: service)
    case "benchmark-worker":
      try runBenchmarkWorker(arguments, service: service)
    case "profile-exports":
      try runProfileExports(arguments, service: service)
    case "swiftbar":
      try printSwiftBar(service: service)
    default:
      throw ControllerError.usage("unknown command: \(command)")
    }
  }
}
