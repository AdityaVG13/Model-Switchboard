import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
  static func runCapabilities() throws {
    try printJSONObject([
      "schema_version": "1", "tool": "ModelSwitchboardController", "native": true,
      "commands": [
        "serve", "serve-web", "status", "list", "start", "stop", "restart", "switch", "activate",
        "stop-all", "integrations", "run-integration", "doctor", "diagnose", "health", "triage",
        "capabilities", "benchmark", "benchmark-worker", "profile-exports", "swiftbar",
        "robot-docs",
      ],
    ])
  }

  static func runRobotDocs() {
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
  }
}
