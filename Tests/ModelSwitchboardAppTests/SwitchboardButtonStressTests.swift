import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

@MainActor
@Test func storeBackedButtonsSurviveRepeatedMockedClicks() async throws {
    let iterations = StressTestConfig.iterations()
    let defaults = UserDefaults.standard
    let previousLastActiveProfiles = defaults.object(forKey: "modelswitchboard.last-active-profiles")
    let previousBenchmarkStartedAt = defaults.object(forKey: "modelswitchboard.last-benchmark-started-at")
    defer {
        UserDefaultsTestHelpers.restore(previousLastActiveProfiles, forKey: "modelswitchboard.last-active-profiles", in: defaults)
        UserDefaultsTestHelpers.restore(previousBenchmarkStartedAt, forKey: "modelswitchboard.last-benchmark-started-at", in: defaults)
    }

    let controller = StressController()
    StressURLProtocol.controller = controller
    defer { StressURLProtocol.controller = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StressURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    let store = SwitchboardStore(
        controllerBaseURL: StressTestConfig.baseURL,
        features: .plus,
        autoStartRefresh: false,
        loopbackEndpointProbe: { _ in [] },
        controllerClientFactory: { try ControllerClient(baseURLString: $0, authToken: $1, session: session) },
        cachePayloadWriter: { _, _ in }
    )

    await store.refresh()
    assertStoreClean(store, after: "initial refresh")

    for _ in 0..<iterations {
        await store.refresh()
        assertStoreClean(store, after: "Refresh")
    }

    for _ in 0..<iterations {
        store.controllerBaseURL = StressTestConfig.baseURL
        await store.refresh()
        assertStoreClean(store, after: "Reconnect")
    }

    for _ in 0..<iterations {
        await store.refreshDoctorReport()
        assertStoreClean(store, after: "Run Controller Doctor")
    }

    for _ in 0..<iterations {
        await store.start(StressTestConfig.profile)
        assertStoreClean(store, after: "Start")
    }

    for _ in 0..<iterations {
        await store.stop(StressTestConfig.profile)
        assertStoreClean(store, after: "Stop")
    }

    for _ in 0..<iterations {
        await store.restart(StressTestConfig.profile)
        assertStoreClean(store, after: "Restart")
    }

    for _ in 0..<iterations {
        await store.activate(StressTestConfig.profile)
        assertStoreClean(store, after: "Activate")
    }

    for _ in 0..<iterations {
        await store.stopAll()
        assertStoreClean(store, after: "Stop All")
    }

    let integration = StressController.integration
    for _ in 0..<iterations {
        await store.runIntegration(integration)
        assertStoreClean(store, after: "Sync Droid")
    }

    for _ in 0..<iterations {
        store.lastBenchmarkStartedAt = nil
        store.benchmark = StressController.idleBenchmark
        await store.quickBenchmark()
        assertStoreClean(store, after: "Benchmark All")
    }

    for _ in 0..<iterations {
        store.lastBenchmarkStartedAt = nil
        store.benchmark = StressController.idleBenchmark
        await store.quickBenchmark([StressTestConfig.profile])
        assertStoreClean(store, after: "Benchmark Profile")
    }

    for _ in 0..<iterations {
        store.statuses = [StressController.status(running: false, ready: false)]
        store.lastActiveProfiles = [StressTestConfig.profile]
        await store.reopenLastActive()
        assertStoreClean(store, after: "Reopen Last")
    }

    let counts = controller.countsSnapshot()
    #expect(counts["POST /api/start"] == iterations * 2)
    #expect(counts["POST /api/stop"] == iterations)
    #expect(counts["POST /api/restart"] == iterations)
    #expect(counts["POST /api/switch"] == iterations)
    #expect(counts["POST /api/stop-all"] == iterations)
    #expect(counts["POST /api/integrations/run"] == iterations)
    #expect(counts["POST /api/benchmark/start"] == iterations * 2)
    #expect((counts["GET /api/status"] ?? 0) > iterations)
    #expect(controller.unhandledRequestsSnapshot().isEmpty)
}

@Test func inspectorPanelButtonsSurviveRepeatedToggles() {
    let iterations = StressTestConfig.iterations()
    var coordinator = InspectorPanelCoordinator<StressPanel>()

    for _ in 0..<iterations {
        #expect(coordinator.toggle(.settings) == .settings)
        #expect(coordinator.toggle(.settings) == nil)
        #expect(coordinator.toggle(.help) == .help)
        #expect(coordinator.toggle(.benchmarks) == .benchmarks)
        coordinator.requestDeferredClose(of: .benchmarks)
        #expect(coordinator.commitDeferredClose(of: .benchmarks) == nil)
    }

    #expect(coordinator.show(.settings) == .settings)
    coordinator.reset()
    #expect(coordinator.show(nil) == nil)
}

@MainActor
@Test func profileActionTimeoutMentionsProfileDiagnostics() {
    let message = SwitchboardStore.userFacingErrorDescription(
        for: URLError(.timedOut),
        actionName: "Start",
        status: StressController.status(running: true, ready: false),
        diagnostic: ProfileDiagnostic(
            profile: StressTestConfig.profile,
            displayName: "Stress Profile",
            runtime: "llama.cpp",
            runtimeLabel: "llama.cpp",
            runtimeTags: ["llama.cpp"],
            launchMode: "adapter",
            errors: ["llama-server not found in controller PATH; set SERVER_BIN to an absolute executable path"],
            warnings: [],
            running: false,
            ready: false,
            pid: nil,
            baseURL: "http://127.0.0.1:8999/v1"
        )
    )

    #expect(message == "Start timed out for Stress Profile. Profile issue: llama-server not found in controller PATH; set SERVER_BIN to an absolute executable path")
}

@MainActor
@Test func failedBenchmarkStartDoesNotArmCooldown() async {
    let defaults = UserDefaults.standard
    let previousBenchmarkStartedAt = defaults.object(forKey: "modelswitchboard.last-benchmark-started-at")
    defer {
        UserDefaultsTestHelpers.restore(previousBenchmarkStartedAt, forKey: "modelswitchboard.last-benchmark-started-at", in: defaults)
    }
    defaults.removeObject(forKey: "modelswitchboard.last-benchmark-started-at")

    let store = SwitchboardStore(
        controllerBaseURL: StressTestConfig.baseURL,
        features: .plus,
        autoStartRefresh: false,
        controllerClientFactory: { _, _ in throw URLError(.cannotConnectToHost) },
        cachePayloadWriter: { _, _ in }
    )

    await store.quickBenchmark([StressTestConfig.profile])

    #expect(store.lastBenchmarkStartedAt == nil)
    #expect(store.benchmarkCooldownRemaining == 0)
    #expect(store.activeBenchmarkProfiles.isEmpty)
}

private enum StressPanel {
    case settings
    case help
    case benchmarks
}

@MainActor
private func assertStoreClean(_ store: SwitchboardStore, after button: String) {
    #expect(store.lastError == nil, "Unexpected error after \(button): \(store.lastError ?? "")")
    #expect(store.pendingProfileActions.isEmpty, "Leaked profile action after \(button)")
    #expect(store.pendingGlobalActions.isEmpty, "Leaked global action after \(button)")
    #expect(store.pendingIntegrationActions.isEmpty, "Leaked integration action after \(button)")
    #expect(!store.isRefreshing, "Refresh flag leaked after \(button)")
    #expect(!store.isRunningControllerDoctor, "Doctor flag leaked after \(button)")
}
