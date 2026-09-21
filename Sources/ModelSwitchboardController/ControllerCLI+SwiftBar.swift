import Foundation
import ModelSwitchboardCore
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
  static func printSwiftBar(service: ControllerService) throws {
    let payload = try service.statusPayload()
    let counts = ProfileRuntimeCounts(statuses: payload.statuses)
    let executable = CommandLine.arguments[0]
    print("LLMs \(counts.ready)/\(counts.total)")
    print("---")
    print("Ready endpoints: \(counts.ready)/\(counts.total)")
    print("Running processes: \(counts.running)")
    print(
      "Stop all | bash=\(executable) param1=stop-all param2=--root param3=\(service.configuration.root.path) terminal=false refresh=true color=red"
    )
    print("---")
    for item in payload.statuses.boardVisible {
      printSwiftBarRow(item, executable: executable, root: service.configuration.root.path)
    }
  }

  static func printSwiftBarRow(_ item: ModelProfileStatus, executable: String, root: String) {
    let state = item.running ? "RUNNING" : "NOT RUNNING"
    let color = item.ready ? "green" : (item.running ? "orange" : "red")
    print(
      "\(item.displayName.replacingOccurrences(of: "|", with: "/")) [\(state)] | color=\(color)")
    for action in ["start", "stop", "restart"] {
      print(
        "\(action.capitalized) \(item.profile) | bash=\(executable) param1=\(action) param2=\(item.profile) param3=--root param4=\(root) terminal=false refresh=true"
      )
    }
    let pid = item.pid.map { String($0) } ?? "-"
    let rss = item.rssMB.map { String($0) } ?? "n/a"
    print("Port \(item.port) • PID \(pid) • RSS \(rss) MB")
    print("---")
  }
}
