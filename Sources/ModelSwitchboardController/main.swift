import Foundation
import ModelSwitchboardControllerCore

@main
enum ModelSwitchboardControllerMain {
  static func main() {
    do {
      try run()
    } catch {
      FileHandle.standardError.write(Data("ModelSwitchboardController: \(error)\n".utf8))
      exit(exitCode(for: error))
    }
  }

  private static func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let knownCommands = Set([
      "serve", "serve-web", "status", "list", "start", "stop", "restart", "switch", "activate",
      "stop-all", "integrations", "run-integration", "doctor", "diagnose", "health", "triage",
      "capabilities", "benchmark", "benchmark-worker", "profile-exports", "swiftbar", "robot-docs",
      "docs",
    ])
    let command: String
    if arguments.contains("--capabilities") {
      command = "capabilities"
    } else if arguments.contains("--robot-docs") || arguments.contains("--robot-help") {
      command = "robot-docs"
    } else if arguments.contains("--robot-triage") {
      command = "triage"
    } else {
      command = arguments.first(where: { knownCommands.contains($0) }) ?? "serve"
    }
    let configuration = try ControllerConfiguration.from(
      arguments: arguments,
      currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
    let service = ControllerService(configuration: configuration)
    switch command {
    case "serve", "serve-web":
      let router = ControllerRouter(service: service, authToken: configuration.authToken)
      let server = ControllerHTTPServer(configuration: configuration, router: router)
      try server.start()
      service.startWatchdog()
      print("controller=http://\(configuration.host):\(configuration.port)")
      dispatchMain()
    case "status":
      let selected = positionalValues(arguments, after: command)
      try printJSON(service.statusPayload(selected: selected.isEmpty ? nil : selected))
    case "list":
      let values = try service.profiles.load().values.sorted { $0.name < $1.name }.map { profile in
        [
          "profile": profile.name, "display_name": profile.displayName, "runtime": profile.runtime,
          "request_model": profile.requestModel, "base_url": profile.baseURL,
        ]
      }
      try printJSONObject(["profiles": values])
    case "start", "stop", "restart":
      let names = positionalValues(arguments, after: command)
      guard !names.isEmpty else { throw ControllerError.usage("No profiles selected") }
      let all = try service.profiles.load().keys.sorted()
      let selected = names == ["all"] ? all : names
      if isDryRun(arguments) {
        try printPlan(command: command, profiles: selected)
        return
      }
      for name in selected {
        if command == "start" { try service.start(name) }
        if command == "stop" { try service.stop(name) }
        if command == "restart" { try service.restart(name) }
      }
      try printJSON(service.actionResponse())
    case "switch", "activate":
      guard let name = positionalValues(arguments, after: command).first else {
        throw ControllerError.usage("No profile selected")
      }
      if isDryRun(arguments) {
        try printPlan(command: "switch", profiles: [name])
        return
      }
      try service.switchProfile(name)
      try printJSON(service.actionResponse())
    case "stop-all":
      if isDryRun(arguments) {
        try printPlan(command: "stop-all", profiles: try service.profiles.load().keys.sorted())
        return
      }
      try service.stopAll()
      try printJSON(service.actionResponse())
    case "integrations":
      try printJSONObject(["integrations": encodableObjects(service.integrationStatus())])
    case "run-integration":
      let values = positionalValues(arguments, after: command)
      guard let id = values.first else { throw ControllerError.usage("No integration selected") }
      try service.runIntegration(id, action: values.dropFirst().first ?? "sync")
      try printJSON(service.actionResponse())
    case "doctor", "diagnose", "health":
      if command == "health" || arguments.contains("health") {
        try printJSONObject(service.doctor.healthPayload())
      } else if arguments.contains("capabilities") {
        try printJSONObject(service.doctor.capabilities())
      } else if arguments.contains("robot-docs") {
        print(
          "Use doctor, doctor health, doctor capabilities, doctor explain <id>, doctor --fix --dry-run, and doctor undo <run-id>."
        )
      } else if let index = arguments.firstIndex(of: "explain"),
        arguments.indices.contains(index + 1)
      {
        try printJSONObject(service.doctor.explain(arguments[index + 1]))
      } else if let index = arguments.firstIndex(of: "undo"),
        arguments.indices.contains(index + 1)
      {
        try printJSONObject(service.doctor.undo(arguments[index + 1]))
      } else if arguments.contains("--fix") {
        try printJSONObject(
          service.doctor.applyFixes(
            dryRun: arguments.contains("--dry-run") || arguments.contains("--plan"),
            runID: option("--run-id", in: arguments)))
      } else {
        try printJSON(service.doctor.report())
      }
    case "triage":
      try printJSONObject([
        "health": service.doctor.healthPayload(),
        "profiles": ["names": try service.profiles.load().keys.sorted()],
        "commands": ["status", "doctor", "capabilities"],
      ])
    case "capabilities":
      try printJSONObject([
        "schema_version": "1", "tool": "ModelSwitchboardController", "native": true,
        "commands": [
          "status", "list", "start", "stop", "restart", "switch", "benchmark", "doctor",
          "integrations", "run-integration", "stop-all", "serve",
        ],
      ])
    case "robot-docs", "docs":
      print(
        """
        Model Switchboard native controller

        Read-only probes:
        - ModelSwitchboardController triage --root Controller
        - ModelSwitchboardController capabilities --root Controller
        - ModelSwitchboardController status --root Controller
        - ModelSwitchboardController doctor --root Controller

        Mutations support --dry-run or --plan before start, stop, restart, switch, and stop-all.
        """)
    case "benchmark":
      let selected = option("--profiles", in: arguments)?.split(separator: ",").map(String.init)
      if isDryRun(arguments) {
        try printPlan(command: "benchmark", profiles: selected ?? [])
        return
      }
      let status = try service.benchmarks.start(
        profiles: selected,
        suite: option("--suite", in: arguments) ?? "quick",
        allowConcurrent: arguments.contains("--allow-concurrent"),
        keepRunning: arguments.contains("--keep-running")
      )
      try printJSON(status)
    case "benchmark-worker":
      let selected = option("--profiles", in: arguments)?.split(separator: ",").map(String.init)
      try service.benchmarks.runWorker(
        selectedNames: selected,
        suite: option("--suite", in: arguments) ?? "quick",
        allowConcurrent: arguments.contains("--allow-concurrent"),
        keepRunning: arguments.contains("--keep-running")
      )
    case "profile-exports":
      guard let path = option("--profile-file", in: arguments) else {
        throw ControllerError.usage("missing value for --profile-file")
      }
      let profile = try service.profiles.load(file: URL(fileURLWithPath: path))
      for key in profile.values.keys.sorted() {
        print("export \(key)=\(shellQuote(profile.values[key] ?? ""))")
      }
    case "swiftbar":
      try printSwiftBar(service: service)
    default:
      throw ControllerError.usage("unknown command: \(command)")
    }
  }

  private static func positionalValues(_ arguments: [String], after command: String) -> [String] {
    guard let commandIndex = arguments.firstIndex(of: command) else { return [] }
    let optionsWithValues = Set([
      "--root", "--host", "--unsafe-bind", "--port", "--auth-token", "--auth-token-file", "--suite",
      "--profiles", "--profile-file", "--run-id",
    ])
    var result: [String] = []
    var skipNext = false
    for argument in arguments.dropFirst(commandIndex + 1) {
      if skipNext {
        skipNext = false
        continue
      }
      if optionsWithValues.contains(argument) {
        skipNext = true
        continue
      }
      if argument.hasPrefix("-") { continue }
      result.append(argument)
    }
    return result
  }

  private static func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  private static func printJSON<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try JSONSupport.data(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func printJSONObject(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSupport.data(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func encodableObjects<T: Encodable>(_ values: [T]) throws -> [Any] {
    try JSONSerialization.jsonObject(with: JSONSupport.data(values)) as? [Any] ?? []
  }

  private static func exitCode(for error: Error) -> Int32 {
    guard let controllerError = error as? ControllerError else { return 1 }
    switch controllerError {
    case .usage: return 64
    case .profileConflict: return 5
    case .invalidConfiguration: return 4
    default: return 1
    }
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func printSwiftBar(service: ControllerService) throws {
    let payload = try service.statusPayload()
    let ready = payload.statuses.filter(\.ready).count
    let running = payload.statuses.filter(\.running).count
    let executable = CommandLine.arguments[0]
    print("LLMs \(ready)/\(payload.statuses.count)")
    print("---")
    print("Ready endpoints: \(ready)/\(payload.statuses.count)")
    print("Running processes: \(running)")
    print(
      "Stop all | bash=\(executable) param1=stop-all param2=--root param3=\(service.configuration.root.path) terminal=false refresh=true color=red"
    )
    print("---")
    for item in payload.statuses {
      let state = item.running ? "RUNNING" : "NOT RUNNING"
      let color = item.ready ? "green" : (item.running ? "orange" : "red")
      print(
        "\(item.displayName.replacingOccurrences(of: "|", with: "/")) [\(state)] | color=\(color)")
      for action in ["start", "stop", "restart"] {
        print(
          "\(action.capitalized) \(item.profile) | bash=\(executable) param1=\(action) param2=\(item.profile) param3=--root param4=\(service.configuration.root.path) terminal=false refresh=true"
        )
      }
      let pid = item.pid.map { String($0) } ?? "-"
      let rss = item.rssMB.map { String($0) } ?? "n/a"
      print("Port \(item.port) • PID \(pid) • RSS \(rss) MB")
      print("---")
    }
  }

  private static func isDryRun(_ arguments: [String]) -> Bool {
    arguments.contains("--dry-run") || arguments.contains("--plan")
  }

  private static func printPlan(command: String, profiles: [String]) throws {
    try printJSONObject([
      "schema_version": "1",
      "tool": "ModelSwitchboardController",
      "command": command,
      "dry_run": true,
      "status": "planned",
      "ok": true,
      "plan": profiles.map { ["action": command, "profile": $0] },
      "results": [],
    ])
  }
}
