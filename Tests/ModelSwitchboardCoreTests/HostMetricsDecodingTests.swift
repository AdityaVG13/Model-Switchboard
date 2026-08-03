import Foundation
import Testing
@testable import ModelSwitchboardCore

@Test func hostMetricsPayloadDecodesSparkStyleJSON() throws {
    let json = """
    {
      "host": "spark",
      "collected_at": "2026-08-03T12:00:00Z",
      "cpu_percent": 18.5,
      "memory": { "used_mb": 32768.0, "total_mb": 131072.0, "percent": 25.0, "source": "proc" },
      "gpus": [
        {
          "index": 0,
          "name": "NVIDIA GB10",
          "util_percent": 42.0,
          "temp_c": 51.0,
          "vram_used_mb": 55296.0,
          "vram_total_mb": 131072.0
        }
      ],
      "gpu_source": "nvidia-smi",
      "processes": [{ "pid": 4242, "vram_mb": 54000.0 }],
      "agent_version": "1.1.2"
    }
    """.data(using: .utf8)!

    let payload = try JSONDecoder().decode(HostMetricsPayload.self, from: json)
    #expect(payload.host == "spark")
    #expect(payload.cpuPercent == 18.5)
    #expect(payload.memory?.usedMB == 32768)
    #expect(payload.gpus.count == 1)
    #expect(payload.gpus[0].vramUsedMB == 55296)
    #expect(payload.gpuSource == "nvidia-smi")
    #expect(payload.processes.first?.pid == 4242)
}

@Test func modelProfileStatusDecodesOptionalVRAM() throws {
    let json = """
    {
      "profile": "qwen",
      "display_name": "Qwen",
      "runtime": "llama.cpp",
      "host": "127.0.0.1",
      "port": "8080",
      "base_url": "http://127.0.0.1:8080/v1",
      "request_model": "qwen",
      "server_model_id": "qwen",
      "pid": 9,
      "running": true,
      "ready": true,
      "server_ids": ["qwen"],
      "rss_mb": 2048.0,
      "vram_mb": 55296.0,
      "log_path": "/tmp/qwen.log"
    }
    """.data(using: .utf8)!

    let status = try JSONDecoder().decode(ModelProfileStatus.self, from: json)
    #expect(status.vramMB == 55296)
    #expect(status.rssMB == 2048)
    #expect(status.stateDescription.contains("VRAM"))
}
