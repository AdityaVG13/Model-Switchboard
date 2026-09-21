import Foundation
import ModelSwitchboardCore
import ModelSwitchboardControllerCore

@main
enum ModelSwitchboardControllerMain {
  static let knownCommands = Set([
    "serve", "serve-web", "status", "list", "start", "stop", "restart", "switch", "activate",
    "stop-all", "integrations", "run-integration", "doctor", "diagnose", "health", "triage",
    "capabilities", "benchmark", "benchmark-worker", "profile-exports", "swiftbar", "robot-docs",
    "docs",
  ])

  static func main() {
    do {
      try run()
    } catch {
      FileHandle.standardError.write(Data("ModelSwitchboardController: \(error)\n".utf8))
      exit(exitCode(for: error))
    }
  }

  static func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "json-strings" {
      try runJSONStrings()
      return
    }
    if arguments.first == "openai-models-contains" {
      try runOpenAIModelsContains(arguments)
      return
    }
    let command = resolvedCommand(from: arguments)
    let configuration = try ControllerConfiguration.from(
      arguments: arguments,
      currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
    let service = ControllerService(configuration: configuration)
    try execute(command, arguments: arguments, service: service, configuration: configuration)
  }

  static func resolvedCommand(from arguments: [String]) -> String {
    if arguments.contains("--capabilities") { return "capabilities" }
    if arguments.contains("--robot-docs") || arguments.contains("--robot-help") { return "robot-docs" }
    if arguments.contains("--robot-triage") { return "triage" }
    return arguments.first(where: { knownCommands.contains($0) }) ?? "serve"
  }
}
