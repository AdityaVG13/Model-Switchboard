import Testing
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardCore

@Test func updatingStatusOverridesMutableFieldsOnly() {
    let status = ModelFixtures.profileStatus(
        runtime: "vllm-mlx",
        runtimeLabel: "vLLM-MLX",
        runtimeTags: ["vllm-mlx", "mlx"],
        launchMode: "adapter",
        pid: 123,
        running: false,
        ready: false,
        rssMB: nil,
        command: "serve"
    )

    let updated = status.updating(running: true, ready: false, serverIDs: ["qwen"], rssMB: 2048)

    #expect(updated.profile == status.profile)
    #expect(updated.running)
    #expect(!updated.ready)
    #expect(updated.serverIDs == ["qwen"])
    #expect(updated.rssMB == 2048)
    #expect(updated.command == status.command)
    #expect(updated.runtimeLabel == "vLLM-MLX")
    #expect(updated.runtimeTags == ["vllm-mlx", "mlx"])
    #expect(updated.launchMode == "adapter")
    #expect(updated.stateDescription.hasPrefix("vLLM-MLX"))
}

@Test func profileDisplayOrderKeepsRunningAtTopThenSortsLoopbackPorts() {
    let statuses = [
        ModelFixtures.profileStatus(
            profile: "remote",
            displayName: "Remote",
            runtime: "custom",
            host: "192.168.1.10",
            port: "9000",
            baseURL: "http://192.168.1.10:9000/v1",
            pid: nil,
            running: false,
            ready: false,
            rssMB: nil
        ),
        ModelFixtures.profileStatus(
            profile: "local-8082",
            displayName: "Local 8082",
            runtime: "mlx",
            port: "8082",
            baseURL: "http://127.0.0.1:8082/v1",
            pid: nil,
            running: false,
            ready: false,
            rssMB: nil
        ),
        ModelFixtures.profileStatus(
            profile: "local-8080",
            displayName: "Local 8080",
            host: "localhost",
            pid: nil,
            running: false,
            ready: false,
            rssMB: nil
        ),
        ModelFixtures.profileStatus(
            profile: "running-8081",
            displayName: "Running 8081",
            port: "8081",
            baseURL: "http://127.0.0.1:8081/v1",
            pid: 42,
            running: true,
            ready: false,
            rssMB: nil
        )
    ]

    let ordered = statuses.sorted(by: ModelProfileStatus.compareForDisplay)
    #expect(ordered.map(\.profile) == ["running-8081", "local-8080", "local-8082", "remote"])
}

@Test func profileDisplayOrderPrefersReadyWhenBothProfilesAreRunning() {
    let statuses = [
        ModelFixtures.profileStatus(
            profile: "warming",
            displayName: "Warming",
            port: "8081",
            baseURL: "http://127.0.0.1:8081/v1",
            pid: 1,
            running: true,
            ready: false,
            rssMB: nil
        ),
        ModelFixtures.profileStatus(
            profile: "ready",
            displayName: "Ready",
            pid: 2,
            running: true,
            ready: true,
            rssMB: nil
        )
    ]

    let ordered = statuses.sorted(by: ModelProfileStatus.compareForDisplay)
    #expect(ordered.map(\.profile) == ["ready", "warming"])
}

@Test func loopbackHostDetectionMatchesKnownAddresses() {
    #expect(LoopbackHost.isLoopback("127.0.0.1"))
    #expect(LoopbackHost.isLoopback("localhost"))
    #expect(LoopbackHost.isLoopback("::1"))
    #expect(LoopbackHost.isLoopback("  LOCALHOST  "))
    #expect(!LoopbackHost.isLoopback("192.168.1.1"))
    #expect(ModelFixtures.profileStatus(host: "127.0.0.1").usesLoopbackEndpoint)
    #expect(!ModelFixtures.profileStatus(host: "10.0.0.8", baseURL: "http://10.0.0.8:8081/v1").usesLoopbackEndpoint)
}
