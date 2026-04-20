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
    let payload = try JSONDecoder().decode(ControllerStatusPayload.self, from: Data(json.utf8))
    #expect(payload.statuses.count == 1)
    #expect(payload.statuses[0].displayName == "Qwen3.5 35B A3B Local (llama.cpp)")
    #expect(payload.integrations.first?.id == "droid")
    #expect(payload.profilesDirectory == "/Users/example/controller/model-profiles")
    #expect(payload.controllerRoot == "/Users/example/controller")
    #expect(payload.benchmark?.latest?.rows.first?.decodeTokensPerSec == 119.63)
}

@Test func decodesDoctorReport() throws {
    let json = #"""
    {
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

    let report = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))

    #expect(report.controller.reachable)
    #expect(report.launchAgent.running)
    #expect(report.profilesDirectory == "/Users/example/.model-switchboard/model-profiles")
    #expect(report.profiles.count == 1)
    #expect(report.profiles[0].errors == ["missing MODEL_DIR or MODEL_REPO"])
    #expect(report.profiles[0].warnings == ["base_url is empty; endpoint health checks may fail"])
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
        integrations: [],
        profilesDirectory: "/tmp/model-profiles",
        controllerRoot: "/tmp"
    )
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")

    try ControllerStatusCache.write(payload, cachedAt: Date(timeIntervalSince1970: 1_700_000_000), to: tempURL)
    let cached = try #require(ControllerStatusCache.load(from: tempURL))

    #expect(cached.payload == payload)
    #expect(cached.sourcePaths.profilesDirectory == "/tmp/model-profiles")
    #expect(cached.sourcePaths.controllerRoot == "/tmp")
}

@Test func sourcePathsAreSharedAcrossControllerPayloadTypes() {
    let statusPayload = ControllerStatusPayload(
        statuses: [],
        benchmark: nil,
        integrations: [],
        profilesDirectory: "/tmp/profiles",
        controllerRoot: "/tmp/controller"
    )

    let actionPayload = ControllerActionResponse(
        ok: true,
        statuses: [],
        benchmark: nil,
        integrations: [],
        profilesDirectory: "/tmp/profiles",
        controllerRoot: "/tmp/controller",
        error: nil
    )

    #expect(statusPayload.sourcePaths == actionPayload.sourcePaths)
    #expect(statusPayload.sourcePaths.profilesDirectory == "/tmp/profiles")
    #expect(statusPayload.sourcePaths.controllerRoot == "/tmp/controller")
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

@Test func autoRefreshPolicyUsesIdleCadenceWhenNothingIsLive() {
    let payload = ControllerStatusPayload(
        statuses: [
            ModelProfileStatus(
                profile: "idle",
                displayName: "Idle",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8080",
                baseURL: "http://127.0.0.1:8080/v1",
                requestModel: "idle",
                serverModelID: "idle",
                pid: nil,
                running: false,
                ready: false,
                serverIDs: [],
                rssMB: nil,
                command: nil,
                logPath: "/tmp/idle.log"
            )
        ],
        benchmark: BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil),
        integrations: []
    )

    let policy = AutoRefreshPolicy(payload: payload)

    #expect(policy.mode == .idle)
    #expect(policy.interval == AutoRefreshPolicy.idleInterval)
}

@Test func autoRefreshPolicyUsesActiveCadenceForLiveEndpoints() {
    let payload = ControllerStatusPayload(
        statuses: [
            ModelProfileStatus(
                profile: "active",
                displayName: "Active",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8081",
                baseURL: "http://127.0.0.1:8081/v1",
                requestModel: "active",
                serverModelID: "active",
                pid: 123,
                running: true,
                ready: true,
                serverIDs: ["active"],
                rssMB: 4096,
                command: nil,
                logPath: "/tmp/active.log"
            )
        ],
        benchmark: BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil),
        integrations: []
    )

    let policy = AutoRefreshPolicy(payload: payload)

    #expect(policy.mode == .activeRuntime)
    #expect(policy.interval == AutoRefreshPolicy.activeRuntimeInterval)
}

@Test func autoRefreshPolicyPrioritizesBenchmarksAndPendingActions() {
    let payload = ControllerStatusPayload(
        statuses: [
            ModelProfileStatus(
                profile: "bench",
                displayName: "Bench",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8082",
                baseURL: "http://127.0.0.1:8082/v1",
                requestModel: "bench",
                serverModelID: "bench",
                pid: 456,
                running: true,
                ready: false,
                serverIDs: [],
                rssMB: nil,
                command: nil,
                logPath: "/tmp/bench.log"
            )
        ],
        benchmark: BenchmarkStatus(running: true, pid: 99, logPath: "/tmp/bench-run.log", latest: nil),
        integrations: []
    )

    let benchmarkingPolicy = AutoRefreshPolicy(payload: payload)
    let pendingPolicy = AutoRefreshPolicy(payload: payload, hasPendingActions: true)

    #expect(benchmarkingPolicy.mode == .benchmarking)
    #expect(benchmarkingPolicy.interval == AutoRefreshPolicy.benchmarkingInterval)
    #expect(pendingPolicy.mode == .pendingAction)
    #expect(pendingPolicy.interval == AutoRefreshPolicy.pendingActionInterval)
}

@Test func companionBundleIdentifierMapsBaseToPlus() {
    #expect(
        LoginItemBundleIdentifiers.companion(for: "io.modelswitchboard.app") == "io.modelswitchboard.plus"
    )
}

@Test func companionBundleIdentifierMapsPlusToBase() {
    #expect(
        LoginItemBundleIdentifiers.companion(for: "io.modelswitchboard.plus") == "io.modelswitchboard.app"
    )
}

@Test func companionBundleIdentifierMappingIsBidirectional() {
    let base = "io.modelswitchboard.app"
    let plus = "io.modelswitchboard.plus"

    let mappedFromBase = LoginItemBundleIdentifiers.companion(for: base)
    let mappedFromPlus = LoginItemBundleIdentifiers.companion(for: plus)

    #expect(mappedFromBase == plus)
    #expect(mappedFromPlus == base)
    #expect(mappedFromBase.flatMap(LoginItemBundleIdentifiers.companion(for:)) == base)
    #expect(mappedFromPlus.flatMap(LoginItemBundleIdentifiers.companion(for:)) == plus)
}

@Test func companionBundleIdentifierReturnsNilForUnknownSuffix() {
    #expect(LoginItemBundleIdentifiers.companion(for: "io.modelswitchboard.desktop") == nil)
}
