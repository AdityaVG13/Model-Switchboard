import Foundation
import ModelSwitchboardCore

extension DoctorService {
  func expectedExecutable(_ profile: ControllerProfile) -> String? {
    switch profile.runtime {
    case "llama.cpp", "turboquant": return "llama-server"
    case "mlx": return "mlx_lm.server"
    case "vllm-mlx": return "vllm-mlx"
    case "ollama": return "ollama"
    case "vllm": return "vllm"
    case "sglang": return "python3"
    default: return nil
    }
  }

  func executableAvailable(_ executable: String, profile: ControllerProfile) -> Bool {
    let configured = ["SERVER_BIN", "LLAMA_SERVER_BIN", "MLX_SERVER_BIN", "VLLM_MLX_BIN"]
      .compactMap { profile[$0] }.contains {
        fileManager.isExecutableFile(atPath: NSString(string: $0).expandingTildeInPath)
      }
    if configured { return true }
    return (try? ProcessRunner.run("/usr/bin/which", [executable], check: false).status) == 0
  }

  func remediation(for message: String) -> String {
    if message.contains("also configured") { return "Assign every profile a unique host and port." }
    if message.contains("missing MODEL") { return "Configure a model source in the profile." }
    if message.contains("not found") {
      return "Install the runtime or configure its executable path."
    }
    if message.contains("health check") { return "Configure an enabled loopback health check." }
    return "Correct the profile configuration and rerun doctor."
  }
}
