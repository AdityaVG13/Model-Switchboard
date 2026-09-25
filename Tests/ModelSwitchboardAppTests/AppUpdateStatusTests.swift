import Foundation
import Testing

@testable import ModelSwitchboardApp

@Suite(.serialized)
@MainActor
struct AppUpdateStatusTests {

    @Test func updateCheckFindsNewerRelease() async {
        let status = updateTestStatus(currentVersion: "2.0.0")
        await status.checkIfDue()
        let release = try? #require(status.available)
        #expect(release?.version == "9.9.9")
        #expect(release?.url.absoluteString.contains("releases/latest") == true)
    }

    @Test func updateCheckStaysSilentWhenCurrentOrAhead() async {
        let current = updateTestStatus(
            currentVersion: "9.9.9", tagJSON: #"{"tag_name":"v9.9.9"}"#)
        await current.checkIfDue()
        #expect(current.available == nil)

        let ahead = updateTestStatus(
            currentVersion: "9.9.10", tagJSON: #"{"tag_name":"v9.9.9"}"#)
        await ahead.checkIfDue()
        #expect(ahead.available == nil)
    }

    @Test func updateCheckSkipsNonNumericVersions() async {
        // Dev builds report "dev"; junk tags must not paint an update row.
        let dev = updateTestStatus(currentVersion: "dev")
        await dev.checkIfDue()
        #expect(dev.available == nil)
        #expect(UpdateStubURLProtocol.requestCount == 0)

        let junk = updateTestStatus(tagJSON: #"{"tag_name":"not-a-version"}"#)
        await junk.checkIfDue()
        #expect(junk.available == nil)
    }

    @Test func updateCheckGatesOnWeeklyInterval() async {
        let defaults = UserDefaults(suiteName: "test.appupdate.\(UUID().uuidString)")!
        let status = updateTestStatus(defaults: defaults)
        await status.checkIfDue()
        #expect(UpdateStubURLProtocol.requestCount == 1)
        await status.checkIfDue()
        #expect(UpdateStubURLProtocol.requestCount == 1)
        #expect(status.available != nil)
    }

    @Test func updateCheckFailsSilent() async {
        let offline = updateTestStatus(tagJSON: nil)
        await offline.checkIfDue()
        #expect(offline.available == nil)

        let rateLimited = updateTestStatus(statusCode: 403)
        await rateLimited.checkIfDue()
        #expect(rateLimited.available == nil)
    }
}

private final class UpdateStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var payload: Data?
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "updates.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        guard let payload = Self.payload else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private func updateTestStatus(
    currentVersion: String = "2.0.0",
    tagJSON: String? = #"{"tag_name":"v9.9.9"}"#,
    statusCode: Int = 200,
    defaults: UserDefaults? = nil
) -> AppUpdateStatus {
    UpdateStubURLProtocol.payload = tagJSON.map { Data($0.utf8) }
    UpdateStubURLProtocol.statusCode = statusCode
    UpdateStubURLProtocol.requestCount = 0
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UpdateStubURLProtocol.self]
    return AppUpdateStatus(
        currentVersion: currentVersion,
        session: URLSession(configuration: configuration),
        endpoint: URL(string: "https://updates.test/releases/latest")!,
        defaults: defaults ?? UserDefaults(suiteName: "test.appupdate.\(UUID().uuidString)")!
    )
}


