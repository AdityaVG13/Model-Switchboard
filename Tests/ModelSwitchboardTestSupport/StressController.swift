import Foundation
import ModelSwitchboardCore

public final class StressController: @unchecked Sendable {
    public static let integration = ControllerIntegration(
        id: "droid",
        displayName: "Factory Droid",
        kind: "model_registry",
        capabilities: ["sync"],
        syncLabel: "Sync Droid",
        description: "Mocked sync target"
    )
    public static let idleBenchmark = BenchmarkStatus(running: false, pid: nil, logPath: nil, latest: nil)

    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var unhandledRequests: [String] = []

    public init() {}

    public func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
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

    public func countsSnapshot() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }

    public func unhandledRequestsSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return unhandledRequests
    }

    public static func status(running: Bool, ready: Bool) -> ModelProfileStatus {
        ModelProfileStatus(
            profile: StressTestConfig.profile,
            displayName: "Stress Profile",
            runtime: "mock",
            runtimeLabel: "Mock",
            runtimeTags: ["mock", "non-destructive"],
            launchMode: "external",
            host: "127.0.0.1",
            port: "8999",
            baseURL: "http://127.0.0.1:8999/v1",
            requestModel: StressTestConfig.profile,
            serverModelID: StressTestConfig.profile,
            pid: running ? 4242 : nil,
            running: running,
            ready: ready,
            serverIDs: ready ? [StressTestConfig.profile] : [],
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
                url: "\(StressTestConfig.baseURL)/api/status",
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
                    profile: StressTestConfig.profile,
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

public final class StressURLProtocol: URLProtocol {
    nonisolated(unsafe) public static var controller: StressController?

    public override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "model-switchboard-button-stress.test"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
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

    public override func stopLoading() {}
}
