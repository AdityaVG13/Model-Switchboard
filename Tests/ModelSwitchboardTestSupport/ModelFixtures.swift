import Foundation
import ModelSwitchboardCore

public enum ModelFixtures {
    public static func profileStatus(
        profile: String = "qwen",
        displayName: String = "Qwen",
        runtime: String = "llama.cpp",
        runtimeLabel: String? = "llama.cpp",
        runtimeTags: [String]? = nil,
        launchMode: String? = nil,
        host: String = "127.0.0.1",
        port: String = "8080",
        baseURL: String = "http://127.0.0.1:8080/v1",
        pid: Int? = 42,
        running: Bool = true,
        ready: Bool = true,
        rssMB: Double? = 4096,
        command: String? = nil,
        logPath: String = "/tmp/qwen.log"
    ) -> ModelProfileStatus {
        ModelProfileStatus(
            profile: profile,
            displayName: displayName,
            runtime: runtime,
            runtimeLabel: runtimeLabel,
            runtimeTags: runtimeTags,
            launchMode: launchMode,
            host: host,
            port: port,
            baseURL: baseURL,
            requestModel: profile,
            serverModelID: profile,
            pid: running ? pid : nil,
            running: running,
            ready: ready,
            serverIDs: running ? [profile] : [],
            rssMB: running ? rssMB : nil,
            command: command,
            logPath: logPath
        )
    }

    public static func statusPayload(
        statuses: [ModelProfileStatus],
        benchmark: BenchmarkStatus? = BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil),
        integrations: [ControllerIntegration] = [],
        profilesDirectory: String? = nil,
        controllerRoot: String? = nil
    ) -> ControllerStatusPayload {
        ControllerStatusPayload(
            statuses: statuses,
            benchmark: benchmark,
            integrations: integrations,
            profilesDirectory: profilesDirectory,
            controllerRoot: controllerRoot
        )
    }

    public static let controllerPayloadJSON = #"""
    {
      "statuses": [
        {
          "profile": "qwen35-a3b",
          "display_name": "Qwen3.5 35B A3B Local (llama.cpp)",
          "runtime": "llama.cpp",
          "runtime_label": "llama.cpp",
          "runtime_tags": ["llama.cpp", "managed", "openai-compatible", "gguf", "metal"],
          "launch_mode": "adapter",
          "host": "127.0.0.1",
          "port": "8080",
          "base_url": "http://127.0.0.1:8080/v1",
          "request_model": "qwen35-local",
          "server_model_id": "qwen35-local",
          "pid": 123,
          "running": true,
          "ready": true,
          "server_ids": ["qwen35-local"],
          "rss_mb": 21613.4,
          "command": "llama-server ...",
          "log_path": "/tmp/qwen35-local.log"
        }
      ],
      "integrations": [
        {
          "id": "droid",
          "display_name": "Factory Droid",
          "kind": "model_registry",
          "capabilities": ["sync"],
          "sync_label": "Sync Droid",
          "description": "Sync managed local profiles into Factory Droid custom model settings."
        }
      ],
      "profiles_dir": "/Users/example/controller/model-profiles",
      "controller_root": "/Users/example/controller",
      "benchmark": {
        "running": false,
        "pid": null,
        "log_path": "/tmp/model-benchmark.log",
        "latest": {
          "generated_at": "2026-04-16T21:20:04Z",
          "suite": "quick",
          "profiles": ["qwen35-a3b"],
          "rows": [
            {
              "profile": "qwen35-a3b",
              "runtime": "llama.cpp",
              "ttft_ms": 70.2,
              "decode_tokens_per_sec": 119.63,
              "e2e_tokens_per_sec": 68.4,
              "rss_mb": 22583.2
            }
          ],
          "json_path": "/tmp/latest.json",
          "markdown_path": "/tmp/latest.md"
        }
      }
    }
    """#

    public static let doctorReportJSON = #"""
    {
      "schema_version": "1",
      "doctor_contract_version": "1.0",
      "tool_version": "1.2.0",
      "generated_at": "2026-07-09T20:00:00Z",
      "healthy": false,
      "findings": [
        {
          "id": "fm-profile-example-mlx-missing-model",
          "severity": "P1",
          "subsystem": "profiles",
          "message": "missing MODEL_DIR or MODEL_REPO",
          "evidence": "example-mlx",
          "remediation": "Set MODEL_DIR or MODEL_REPO in the profile",
          "auto_fixable": false
        }
      ],
      "next_steps": [
        "Fix missing model sources reported by doctor"
      ],
      "controller": {
        "url": "http://127.0.0.1:8877/api/status",
        "reachable": true,
        "profiles": 3,
        "integrations": 1
      },
      "launch_agent": {
        "plist_path": "/Users/example/Library/LaunchAgents/io.modelswitchboard.controller.plist",
        "installed": true,
        "running": true
      },
      "integrations": [],
      "profiles_dir": "/Users/example/.model-switchboard/model-profiles",
      "controller_root": "/Users/example/.model-switchboard",
      "profiles": [
        {
          "profile": "example-mlx",
          "display_name": "Example MLX Model",
          "runtime": "mlx",
          "runtime_label": "MLX",
          "runtime_tags": ["mlx", "managed", "openai-compatible", "apple-silicon"],
          "launch_mode": "adapter",
          "errors": ["missing MODEL_DIR or MODEL_REPO"],
          "warnings": ["base_url is empty; endpoint health checks may fail"],
          "running": false,
          "ready": false,
          "pid": null,
          "base_url": ""
        }
      ]
    }
    """#
}
