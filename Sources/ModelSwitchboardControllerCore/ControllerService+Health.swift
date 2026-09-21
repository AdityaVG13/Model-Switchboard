import Foundation
import ModelSwitchboardCore

extension ControllerService {
    func processMatches(_ pid: Int, profile: ControllerProfile) -> Bool {
        if pid == Int(ProcessInfo.processInfo.processIdentifier) { return false }
        guard let command = processCommand(pid)?.lowercased() else { return false }
        let markers = [
            profile.name, profile["MODEL_ALIAS"], profile.requestModel, profile.serverModelID,
            profile["MODEL_PATH"], profile["MODEL_DIR"], profile["MODEL_FILE"], profile["MODEL_REPO"],
        ]
        return markers.compactMap { $0?.lowercased() }.contains {
            $0.count >= 4 && command.contains($0)
        }
    }

    func commandLooksLikeModelServer(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else { return false }
        let lowered = command.lowercased()
        let markers = [
            "llama-server", "llama.cpp", "llamacpp", "vllm", "sglang", "ollama",
            "tabbyapi", "aphrodite", "mlx", "mlc_llm", "koboldcpp", "kobold", "exllama",
            "tgi-", "openai-compatible", "lmdeploy", "tensorrt", "trtllm", "localai", "gguf",
        ]
        return markers.contains { lowered.contains($0) }
    }
}
