import Foundation
import Testing
@testable import ModelSwitchboardCore

@Test func decodesControllerPayload() throws {
    let json = #"""
    {
      "statuses": [
        {
          "profile": "qwen35-a3b",
          "display_name": "Qwen3.5 35B A3B Local (llama.cpp)",
          "runtime": "llama.cpp",
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
    let payload = try JSONDecoder().decode(ControllerStatusPayload.self, from: Data(json.utf8))
    #expect(payload.statuses.count == 1)
    #expect(payload.statuses[0].displayName == "Qwen3.5 35B A3B Local (llama.cpp)")
    #expect(payload.integrations.first?.id == "droid")
    #expect(payload.benchmark?.latest?.rows.first?.decodeTokensPerSec == 119.63)
}

@Test func summaryChoosesBenchmarkLabel() {
    let payload = ControllerStatusPayload(
        statuses: [
            ModelProfileStatus(
                profile: "qwen35-a3b",
                displayName: "Qwen",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8080",
                baseURL: "http://127.0.0.1:8080/v1",
                requestModel: "qwen",
                serverModelID: "qwen",
                pid: 1,
                running: true,
                ready: true,
                serverIDs: ["qwen"],
                rssMB: 123.4,
                command: nil,
                logPath: "/tmp/qwen.log"
            )
        ],
        benchmark: BenchmarkStatus(running: true, pid: 42, logPath: "/tmp/bench.log", latest: nil),
        integrations: []
    )
    let summary = DashboardSummary(payload: payload)
    #expect(summary.menuBarTitle == "Bench 1/1")
    #expect(summary.menuBarSystemImage == "speedometer")
}

@Test func summaryUsesReadyLabelWhenNotBenchmarking() {
    let payload = ControllerStatusPayload(
        statuses: [
            ModelProfileStatus(
                profile: "gemma",
                displayName: "Gemma",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8082",
                baseURL: "http://127.0.0.1:8082/v1",
                requestModel: "gemma",
                serverModelID: "gemma",
                pid: nil,
                running: false,
                ready: true,
                serverIDs: ["gemma"],
                rssMB: nil,
                command: nil,
                logPath: "/tmp/gemma.log"
            )
        ],
        benchmark: BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil),
        integrations: []
    )
    let summary = DashboardSummary(payload: payload)
    #expect(summary.menuBarTitle == "Ready 1/1")
    #expect(summary.menuBarSystemImage == "memorychip.fill")
}

@Test func summaryUsesChipOutlineWhileStarting() {
    let payload = ControllerStatusPayload(
        statuses: [
            ModelProfileStatus(
                profile: "qwen",
                displayName: "Qwen",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8080",
                baseURL: "http://127.0.0.1:8080/v1",
                requestModel: "qwen",
                serverModelID: "qwen",
                pid: 123,
                running: true,
                ready: false,
                serverIDs: [],
                rssMB: nil,
                command: nil,
                logPath: "/tmp/qwen.log"
            )
        ],
        benchmark: BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil),
        integrations: []
    )
    let summary = DashboardSummary(payload: payload)
    #expect(summary.menuBarSystemImage == "memorychip")
}

@Test func cacheRoundTripPreservesPayload() throws {
    let status = ModelProfileStatus(
        profile: "gemma",
        displayName: "Gemma",
        runtime: "llama.cpp",
        host: "127.0.0.1",
        port: "8081",
        baseURL: "http://127.0.0.1:8081/v1",
        requestModel: "gemma",
        serverModelID: "gemma",
        pid: nil,
        running: false,
        ready: false,
        serverIDs: [],
        rssMB: nil,
        command: nil,
        logPath: "/tmp/gemma.log"
    )
    let payload = ControllerStatusPayload(
        statuses: [status],
        benchmark: BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil),
        integrations: []
    )
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")

    try ControllerStatusCache.write(payload, cachedAt: Date(timeIntervalSince1970: 1_700_000_000), to: tempURL)
    let cached = try #require(ControllerStatusCache.load(from: tempURL))

    #expect(cached.payload == payload)
}

@Test func updatingStatusOverridesMutableFieldsOnly() {
    let status = ModelProfileStatus(
        profile: "qwen",
        displayName: "Qwen",
        runtime: "llama.cpp",
        host: "127.0.0.1",
        port: "8080",
        baseURL: "http://127.0.0.1:8080/v1",
        requestModel: "qwen",
        serverModelID: "qwen",
        pid: 123,
        running: false,
        ready: false,
        serverIDs: [],
        rssMB: nil,
        command: "serve",
        logPath: "/tmp/qwen.log"
    )

    let updated = status.updating(running: true, ready: false, serverIDs: ["qwen"], rssMB: 2048)

    #expect(updated.profile == status.profile)
    #expect(updated.running)
    #expect(!updated.ready)
    #expect(updated.serverIDs == ["qwen"])
    #expect(updated.rssMB == 2048)
    #expect(updated.command == status.command)
}
