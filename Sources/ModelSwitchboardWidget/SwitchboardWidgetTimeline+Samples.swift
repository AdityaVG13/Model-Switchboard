import WidgetKit
import ModelSwitchboardCore

extension SwitchboardTimelineProvider {
    var sampleStatuses: [ModelProfileStatus] {
        [
            ModelProfileStatus(
                profile: "qwen35-a3b",
                displayName: "Qwen3.5 35B A3B",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8080",
                baseURL: WidgetControllerConfig.defaultBaseURL,
                requestModel: "qwen35-local",
                serverModelID: "qwen35-local",
                pid: 12345,
                running: true,
                ready: true,
                serverIDs: ["qwen35-local"],
                rssMB: 21849.3,
                command: nil,
                logPath: "/tmp/qwen35-local.log"
            ),
            ModelProfileStatus(
                profile: "gemma4-e4b-obliterated",
                displayName: "Gemma 4 E4B",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8082",
                baseURL: "http://127.0.0.1:8082/v1",
                requestModel: "gemma4-local",
                serverModelID: "gemma4-local",
                pid: nil,
                running: false,
                ready: false,
                serverIDs: [],
                rssMB: nil,
                command: nil,
                logPath: "/tmp/gemma.log"
            )
        ]
    }
}
