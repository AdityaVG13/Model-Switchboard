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
