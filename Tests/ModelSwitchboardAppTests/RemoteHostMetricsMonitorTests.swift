import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

// MARK: - URLProtocol stub (host-routed, deterministic)

/// Routes host-metrics fixtures by request host. Thread-safe for concurrent polls.
private final class HostMetricsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var statusByHost: [String: Int] = [:]
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
        guard let host = request.url?.host else { return false }
        return host.hasSuffix(".host-metrics.test")
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
        if (200..<300).contains(status) {
            let json = #"{"host":"\#(host)","cpu_percent":12.5,"gpus":[],"processes":[]}"#
            body = Data(json.utf8)
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
    configuration.waitsForConnectivity = false
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
                controllerClientFactory: { base, auth in
                    try ControllerClient(baseURLString: base, authToken: auth, session: session)
                }
            )
        },
        tokenStorageFactory: { id in
            KeychainTokenStorage(service: service, accessGroup: nil, account: "gateway-\(id)")
        },
        sshExecutableURL: URL(fileURLWithPath: "/usr/bin/true")
    )

    for item in hosts {
        let config = GatewayConfig.direct(
            name: item.name,
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

/// URLProtocol fixture uses process-global routing maps; serialize this suite.
@Suite(.serialized)
struct RemoteHostMetricsMonitorTests {
    @MainActor
    @Test func pollOnceIsolatesErrorsAcrossConcurrentGateways() async throws {
        HostMetricsURLProtocol.reset()
        defer { HostMetricsURLProtocol.reset() }

        let okHost = "ok.host-metrics.test"
        let badHost = "bad.host-metrics.test"
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

            #expect(okEntry.error == nil, "ok error=\(String(describing: okEntry.error)) base=\(okRuntime.store.controllerBaseURL)")
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
            let runtime = try #require(hub.enabledRemoteRuntimes.first)
            #expect(runtime.store.controllerBaseURL.contains(host))

            await monitor.pollOnce()
            let good = monitor.entry(forGatewayID: runtime.id)
            #expect(good.metrics?.cpuPercent == 12.5, "first poll error=\(String(describing: good.error))")
            #expect(good.error == nil)

            HostMetricsURLProtocol.configure(host: host, status: 503)
            await monitor.pollOnce()

            let after = monitor.entry(forGatewayID: runtime.id)
            #expect(after.metrics?.cpuPercent == 12.5, "should keep last good metrics")
            #expect(after.error != nil)
            #expect(after.unsupported == false)
        }
    }
}
