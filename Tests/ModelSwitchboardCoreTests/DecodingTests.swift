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
    #expect(report.profiles[0].runtimeLabel == "MLX")
    #expect(report.profiles[0].runtimeTags?.contains("apple-silicon") == true)
    #expect(report.profiles[0].launchMode == "adapter")
    #expect(report.profiles[0].errors == ["missing MODEL_DIR or MODEL_REPO"])
    #expect(report.profiles[0].warnings == ["base_url is empty; endpoint health checks may fail"])
}
