import Foundation
import Testing
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardCore

@Test func decodesControllerPayload() throws {
    let payload = try JSONDecoder().decode(
        ControllerStatusPayload.self,
        from: Data(ModelFixtures.controllerPayloadJSON.utf8)
    )
    #expect(payload.statuses.count == 1)
    #expect(payload.statuses[0].displayName == "Qwen3.5 35B A3B Local (llama.cpp)")
    #expect(payload.statuses[0].runtimeLabel == "llama.cpp")
    #expect(payload.statuses[0].runtimeTags?.contains("openai-compatible") == true)
    #expect(payload.statuses[0].launchMode == "adapter")
    #expect(payload.integrations.first?.id == "droid")
    #expect(payload.profilesDirectory == "/Users/example/controller/model-profiles")
    #expect(payload.controllerRoot == "/Users/example/controller")
    #expect(payload.benchmark?.latest?.rows.first?.decodeTokensPerSec == 119.63)
}

@Test func decodesBenchmarkRowPrefillCasesAndToleratesTheirAbsence() throws {
    let withCases = """
    {
        "profile": "turbo",
        "runtime": "vLLM MLX",
        "ttft_ms": 953.0,
        "decode_tokens_per_sec": 113.5,
        "e2e_tokens_per_sec": 50.4,
        "rss_mb": 15258,
        "prefill_cases": [
            {"label": "1k", "prompt_est_tokens": 1024, "ttft_ms": 308.0, "decode_tokens_per_sec": 117.4},
            {"label": "8k", "prompt_est_tokens": 8192, "ttft_ms": 1700.0, "decode_tokens_per_sec": 103.3}
        ]
    }
    """
    let row = try JSONDecoder().decode(BenchmarkLatestRow.self, from: Data(withCases.utf8))
    #expect(row.prefillCases?.count == 2)
    #expect(row.prefillCases?.first?.label == "1k")
    #expect(row.prefillCases?.first?.promptEstTokens == 1024)
    #expect(row.prefillCases?.first?.ttftMS == 308.0)
    #expect(row.prefillCases?.last?.decodeTokensPerSec == 103.3)

    // Reports cached before the field existed (and non-context suites) omit the key.
    let withoutCases = """
    {
        "profile": "plain",
        "runtime": "llama.cpp",
        "ttft_ms": 1.0,
        "decode_tokens_per_sec": 2.0,
        "e2e_tokens_per_sec": 3.0,
        "rss_mb": null
    }
    """
    let legacyRow = try JSONDecoder().decode(BenchmarkLatestRow.self, from: Data(withoutCases.utf8))
    #expect(legacyRow.prefillCases == nil)
}

@Test func decodesDoctorReport() throws {
    let report = try JSONDecoder().decode(
        DoctorReport.self,
        from: Data(ModelFixtures.doctorReportJSON.utf8)
    )

    #expect(report.controller.reachable)
    #expect(report.launchAgent.running)
    #expect(report.profilesDirectory == "/Users/example/.model-switchboard/model-profiles")
    #expect(report.profiles.count == 1)
    // L12: the diagnostic is a role-flagged view over the shared snapshot —
    // status facts live in `status` exactly once.
    #expect(report.profiles[0].status.runtimeLabel == "MLX")
    #expect(report.profiles[0].status.runtimeTags?.contains("apple-silicon") == true)
    #expect(report.profiles[0].status.launchMode == "adapter")
    #expect(report.profiles[0].errors == ["missing MODEL_DIR or MODEL_REPO"])
    #expect(report.profiles[0].warnings == ["base_url is empty; endpoint health checks may fail"])
    // L27: healthy is DERIVED from findings (one P1 blocker) — the wire key
    // is gone from the fixture.
    #expect(report.healthy == false)
    #expect(report.findings?.count == 1)
    #expect(report.findings?.first?.id == "fm-profile-example-mlx-missing-model")
    #expect(report.findings?.first?.severity == .p1)
    // L27: autoFixable derives from fixer presence — no fixer means not
    // auto-fixable, and the pair cannot disagree.
    #expect(report.findings?.first?.autoFixable == false)
    #expect(report.nextSteps?.first?.contains("Fix missing model sources") == true)
}

@Test func controllerClientBuildsUnencodedAPIPaths() throws {
    let base = URL(string: "http://127.0.0.1:8877")!
    let statusURL = ControllerClient.apiURL(baseURL: base, path: "/api/status")
    #expect(statusURL.absoluteString == "http://127.0.0.1:8877/api/status")
    #expect(!statusURL.absoluteString.contains("%2F"))

    let switchURL = ControllerClient.apiURL(baseURL: base, path: "api/switch")
    #expect(switchURL.path == "/api/switch")
}

@Test func nullLogPathDecodesToNil() throws {
    let json = """
    {
      "profile": "port-1",
      "display_name": "Demo",
      "runtime": "llama.cpp",
      "host": "127.0.0.1",
      "port": "1",
      "base_url": "http://127.0.0.1:1/v1",
      "request_model": "demo",
      "server_model_id": "demo",
      "pid": null,
      "running": false,
      "ready": false,
      "server_ids": [],
      "rss_mb": null,
      "command": null,
      "log_path": null
    }
    """
    let status = try JSONDecoder().decode(ModelProfileStatus.self, from: Data(json.utf8))
    // L09: parse-at-boundary — absent log_path is nil, not an invented "".
    #expect(status.logPath == nil)
    #expect(status.profile == "port-1")
    #expect(status.origin == .unknown)
}
