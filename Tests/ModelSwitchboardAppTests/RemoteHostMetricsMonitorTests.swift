import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

// MARK: - URLProtocol stub (host-routed, deterministic)

/// Routes `/api/host/metrics` by request host. Thread-safe for concurrent polls.
private final class HostMetricsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    /// host → HTTP status (200 body is a minimal valid HostMetricsPayload JSON).
    nonisolated(unsafe) private static var statusByHost: [String: Int] = [:]
    /// host → artificial delay before responding (seconds).
    nonisolated(unsafe) private static var delayByHost: [String: TimeInterval] = [:]

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusByHost = [:]
        delayByHost = [:]
    }

    static func configure(host: String, status: Int, delay: TimeInterval = 0) {
        lock.lock()
        defer { lock.unlock() }
        statusByHost[host] = status
        delayByHost[host] = delay
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".host-metrics.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let status: Int
        let delay: TimeInterval
        Self.lock.lock()
        status = Self.statusByHost[host] ?? 500
        delay = Self.delayByHost[host] ?? 0
        Self.lock.unlock()

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }

        let body: Data
        if status == 200 {
            body = Data(#"{"host":"\#(host)","cpu_percent":12.5,"gpus":[],"processes":[]}"#.utf8)
        } else {
            body = Data("HTTP \(status)".utf8)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

@MainActor
private func makeMetricsSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HostMetricsURLProtocol.self]
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 5
    return URLSession(configuration: configuration)
}

@MainActor
private func withMetricsHub(
    hosts: [(name: String, host: String)],
    session: URLSession,
    body: @MainActor (GatewayHub, RemoteHostMetricsMonitor) async throws -> Void
) async throws {
    let suiteName = "io.modelswitchboard.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = "io.modelswitchboard.tests.\(UUID().uuidString)"

    let hub = GatewayHub(
        localStore: SwitchboardStore(
            controllerBaseURL: ControllerEndpointDefaults.baseURLString,
            features: .base,
            autoStartRefresh: false,
            controllerClientFactory: { _, _ in throw URLError(.cannotConnectToHost) }
        ),
        defaults: defaults,
        remoteStoreFactory: { config, baseURL, token in
            SwitchboardStore(
                controllerBaseURL: baseURL,
                controllerAuthToken: token,
                features: .base,
                gateway: GatewayContext(config: config),
                autoStartRefresh: false,
                controllerClientFactory: { try ControllerClient(baseURLString: $0, authToken: $1, session: session) }
            )
        },
        tokenStorageFactory: { id in
            KeychainTokenStorage(service: service, accessGroup: nil, account: "gateway-\(id)")
        },
        sshExecutableURL: URL(fileURLWithPath: "/usr/bin/true")
    )

    for item in hosts {
        let config = GatewayConfig(
            name: item.name,
            kind: .direct,
            baseURL: "http://\(item.host):8877"
        )
        hub.upsertGateway(config, token: "token-\(item.name)")
    }
    defer {
        for runtime in hub.remoteRuntimes {
            hub.removeGateway(id: runtime.id)
        }
    }

    let monitor = RemoteHostMetricsMonitor(intervalSeconds: 60)
    monitor.attach(hub: hub)
    try await body(hub, monitor)
}

// MARK: - Tests

@MainActor
@Test func pollOnceIsolatesErrorsAcrossConcurrentGateways() async throws {
    HostMetricsURLProtocol.reset()
    defer { HostMetricsURLProtocol.reset() }

    let okHost = "ok.host-metrics.test"
    let badHost = "bad.host-metrics.test"
    // Slow success so a sequential poll would finish the failure first;
    // isolation only requires both results land correctly after one pollOnce.
    HostMetricsURLProtocol.configure(host: okHost, status: 200, delay: 0.05)
    HostMetricsURLProtocol.configure(host: badHost, status: 404, delay: 0)

    let session = makeMetricsSession()
    defer { session.invalidateAndCancel() }

    try await withMetricsHub(
        hosts: [
            (name: "OK", host: okHost),
            (name: "Bad", host: badHost),
        ],
        session: session
    ) { hub, monitor in
        await monitor.pollOnce()

        let okRuntime = try #require(hub.enabledRemoteRuntimes.first { $0.name == "OK" })
        let badRuntime = try #require(hub.enabledRemoteRuntimes.first { $0.name == "Bad" })

        let okEntry = monitor.entry(forGatewayID: okRuntime.id)
        let badEntry = monitor.entry(forGatewayID: badRuntime.id)

        #expect(okEntry.error == nil)
        #expect(okEntry.unsupported == false)
        #expect(okEntry.metrics?.cpuPercent == 12.5)
        #expect(okEntry.metrics?.host == okHost)

        #expect(badEntry.unsupported == true)
        #expect(badEntry.metrics == nil)
        #expect(badEntry.error?.contains("does not expose host metrics") == true)
    }
}

@MainActor
@Test func pollOncePreservesLastGoodMetricsOnTransientFailure() async throws {
    HostMetricsURLProtocol.reset()
    defer { HostMetricsURLProtocol.reset() }

    let host = "transient.host-metrics.test"
    HostMetricsURLProtocol.configure(host: host, status: 200)

    let session = makeMetricsSession()
    defer { session.invalidateAndCancel() }

    try await withMetricsHub(
        hosts: [(name: "Lab", host: host)],
        session: session
    ) { hub, monitor in
        await monitor.pollOnce()
        let runtime = try #require(hub.enabledRemoteRuntimes.first)
        let good = monitor.entry(forGatewayID: runtime.id)
        #expect(good.metrics?.cpuPercent == 12.5)
        #expect(good.error == nil)

        HostMetricsURLProtocol.configure(host: host, status: 503)
        await monitor.pollOnce()

        let after = monitor.entry(forGatewayID: runtime.id)
        #expect(after.metrics?.cpuPercent == 12.5)
        #expect(after.error != nil)
        #expect(after.unsupported == false)
    }
}
