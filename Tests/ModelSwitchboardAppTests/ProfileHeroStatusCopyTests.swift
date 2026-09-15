import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

@Test func profileHeroStatusCopy() {
    let cases: [(ModelProfileStatus.Lifecycle, String?, String?, String)] = [
        (.starting, nil, nil, "WARMING"),
        (.running, nil, "Spark", "ACTIVE ON SPARK"),
        (.stopped, nil, "Spark", "STOPPED ON SPARK"),
        (.running, "STARTING", "Spark", "STARTING ON SPARK"),
    ]
    for value in cases {
        #expect(ProfileHeroStatusCopy.label(
            lifecycle: value.0,
            pending: value.1, gatewayName: value.2
        ) == value.3)
    }
}

@Test func profileHeroEndpointSubtitleMasksHosts() {
    #expect(
        ProfileHeroStatusCopy.endpointSubtitle(
            runtimeLabel: "vLLM",
            url: "http://gpu.example.ts.net:8050/v1",
            host: "gpu.example.ts.net",
            port: "8050",
            hidden: true
        ) == "vLLM · http://••••:8050/v1"
    )
    #expect(
        ProfileHeroStatusCopy.endpointSubtitle(
            runtimeLabel: "vLLM",
            url: nil,
            host: "spark.local",
            port: "8050",
            hidden: true
        ) == "vLLM · ••••:8050"
    )
    #expect(
        ProfileHeroStatusCopy.endpointSubtitle(
            runtimeLabel: "llama.cpp",
            url: "http://127.0.0.1:8080/v1",
            host: "127.0.0.1",
            port: "8080",
            hidden: false
        ) == "llama.cpp · http://127.0.0.1:8080/v1"
    )
}
