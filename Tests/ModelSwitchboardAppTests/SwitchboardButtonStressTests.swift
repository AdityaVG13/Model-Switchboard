import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

private let stressBaseURL = "http://model-switchboard-button-stress.test"
private let stressProfile = "stress-profile"
private let stressIterationsKey = "MSW_STRESS_BUTTON_CLICKS"

@MainActor
@Test func storeBackedButtonsSurviveRepeatedMockedClicks() async throws {
    let iterations = stressIterations()
    let defaults = UserDefaults.standard
    let previousLastActiveProfiles = defaults.object(forKey: "modelswitchboard.last-active-profiles")
    let previousBenchmarkStartedAt = defaults.object(forKey: "modelswitchboard.last-benchmark-started-at")
    defer {
        restore(previousLastActiveProfiles, forKey: "modelswitchboard.last-active-profiles", in: defaults)
        restore(previousBenchmarkStartedAt, forKey: "modelswitchboard.last-benchmark-started-at", in: defaults)
    }

    let controller = StressController()
    StressURLProtocol.controller = controller
    defer { StressURLProtocol.controller = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StressURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    let store = SwitchboardStore(
        controllerBaseURL: stressBaseURL,
        features: .plus,
        autoStartRefresh: false,
        loopbackEndpointProbe: { _ in [] },
        controllerClientFactory: { try ControllerClient(baseURLString: $0, session: session) },
        cachePayloadWriter: { _, _ in }
    )

    await store.refresh()
    assertStoreClean(store, after: "initial refresh")

    for _ in 0..<iterations {
        await store.refresh()
        assertStoreClean(store, after: "Refresh")
    }

    for _ in 0..<iterations {
        store.controllerBaseURL = stressBaseURL
        await store.refresh()
        assertStoreClean(store, after: "Reconnect")
    }

    for _ in 0..<iterations {
        await store.refreshDoctorReport()
        assertStoreClean(store, after: "Run Controller Doctor")
    }

    for _ in 0..<iterations {
        await store.start(stressProfile)
        assertStoreClean(store, after: "Start")
    }

    for _ in 0..<iterations {
        await store.stop(stressProfile)
        assertStoreClean(store, after: "Stop")
    }

    for _ in 0..<iterations {
        await store.restart(stressProfile)
        assertStoreClean(store, after: "Restart")
    }

    for _ in 0..<iterations {
        await store.activate(stressProfile)
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
        await store.quickBenchmark([stressProfile])
        assertStoreClean(store, after: "Benchmark Profile")
    }

    for _ in 0..<iterations {
        store.statuses = [StressController.status(running: false, ready: false)]
        store.lastActiveProfiles = [stressProfile]
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
    let iterations = stressIterations()
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

private enum StressPanel {
    case settings
    case help
    case benchmarks
}

private func stressIterations() -> Int {
    let rawValue = ProcessInfo.processInfo.environment[stressIterationsKey] ?? "100"
    return max(1, Int(rawValue) ?? 100)
}

private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
    if let value {
        defaults.set(value, forKey: key)
    } else {
        defaults.removeObject(forKey: key)
    }
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

private final class StressURLProtocol: URLProtocol {
    nonisolated(unsafe) static var controller: StressController?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "model-switchboard-button-stress.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let controller = Self.controller else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        do {
            let (response, data) = try controller.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class StressController: @unchecked Sendable {
    static let integration = ControllerIntegration(
        id: "droid",
        displayName: "Factory Droid",
        kind: "model_registry",
        capabilities: ["sync"],
        syncLabel: "Sync Droid",
        description: "Mocked sync target"
    )
    static let idleBenchmark = BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil)

    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var unhandledRequests: [String] = []

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let key = "\(method) \(path)"
        record(key)

        let data: Data
        switch (method, path) {
        case ("GET", "/api/status"):
            data = encode(Self.statusPayload())
        case ("GET", "/api/doctor"):
            data = encode(Self.doctorReport())
        case ("POST", "/api/start"):
            data = encode(Self.actionResponse(running: true, ready: false))
        case ("POST", "/api/stop"):
            data = encode(Self.actionResponse(running: false, ready: false))
        case ("POST", "/api/restart"), ("POST", "/api/switch"):
            data = encode(Self.actionResponse(running: true, ready: false))
        case ("POST", "/api/stop-all"), ("POST", "/api/integrations/run"):
            data = encode(Self.actionResponse(running: false, ready: false))
        case ("POST", "/api/benchmark/start"):
            data = encode(Self.actionResponse(benchmark: BenchmarkStatus(running: true, pid: 9001, logPath: "/tmp/mock-benchmark.log", latest: nil)))
        default:
            recordUnhandled(key)
            data = Data(#"{"error":"not found"}"#.utf8)
        }

        let status = unhandledRequestsSnapshot().contains(key) ? 404 : 200
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    func countsSnapshot() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }

    func unhandledRequestsSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return unhandledRequests
    }

    static func status(running: Bool, ready: Bool) -> ModelProfileStatus {
        ModelProfileStatus(
            profile: stressProfile,
            displayName: "Stress Profile",
            runtime: "mock",
            runtimeLabel: "Mock",
            runtimeTags: ["mock", "non-destructive"],
            launchMode: "external",
            host: "127.0.0.1",
            port: "8999",
            baseURL: "http://127.0.0.1:8999/v1",
            requestModel: stressProfile,
            serverModelID: stressProfile,
            pid: running ? 4242 : nil,
            running: running,
            ready: ready,
            serverIDs: ready ? [stressProfile] : [],
            rssMB: running ? 512 : nil,
            command: nil,
            logPath: "/tmp/stress-profile.log"
        )
    }

    private func record(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }

    private func recordUnhandled(_ key: String) {
        lock.lock()
        unhandledRequests.append(key)
        lock.unlock()
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        try! JSONEncoder().encode(value)
    }

    private static func statusPayload() -> ControllerStatusPayload {
        ControllerStatusPayload(
            statuses: [status(running: false, ready: false)],
            benchmark: idleBenchmark,
            integrations: [integration],
            profilesDirectory: "/tmp/model-switchboard-stress/model-profiles",
            controllerRoot: "/tmp/model-switchboard-stress"
        )
    }

    private static func actionResponse(
        running: Bool = false,
        ready: Bool = false,
        benchmark: BenchmarkStatus? = idleBenchmark
    ) -> ControllerActionResponse {
        ControllerActionResponse(
            ok: true,
            statuses: [status(running: running, ready: ready)],
            benchmark: benchmark,
            integrations: [integration],
            profilesDirectory: "/tmp/model-switchboard-stress/model-profiles",
            controllerRoot: "/tmp/model-switchboard-stress",
            error: nil
        )
    }

    private static func doctorReport() -> DoctorReport {
        DoctorReport(
            controller: ControllerHeartbeat(
                url: "\(stressBaseURL)/api/status",
                reachable: true,
                profiles: 1,
                integrations: 1
            ),
            launchAgent: LaunchAgentStatus(
                plistPath: "/tmp/io.modelswitchboard.controller.plist",
                installed: true,
                running: true
            ),
            integrations: [integration],
            profilesDirectory: "/tmp/model-switchboard-stress/model-profiles",
            controllerRoot: "/tmp/model-switchboard-stress",
            profiles: [
                ProfileDiagnostic(
                    profile: stressProfile,
                    displayName: "Stress Profile",
                    runtime: "mock",
                    runtimeLabel: "Mock",
                    runtimeTags: ["mock", "non-destructive"],
                    launchMode: "external",
                    errors: [],
                    warnings: [],
                    running: false,
                    ready: false,
                    pid: nil,
                    baseURL: "http://127.0.0.1:8999/v1"
                )
            ]
        )
    }
}
