import Foundation
import ModelSwitchboardCore
import Testing

@testable import ModelSwitchboardControllerCore

@Test func frozenControllerContractContainsAllNativeCases() throws {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let fixture = repositoryRoot.appendingPathComponent(
    "Controller/tests/conformance/fixtures/controller_api_cases.json")
  let cases =
    try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]] ?? []
  let ids = Set(cases.compactMap { $0["id"] as? String })
  #expect(
    ids
      == Set([
        "MSB-API-GET-001", "MSB-API-GET-002", "MSB-API-GET-003", "MSB-API-GET-004",
        "MSB-API-AUTH-001", "MSB-API-AUTH-002",
        "MSB-API-ACTION-001", "MSB-API-ACTION-002", "MSB-API-ACTION-003", "MSB-API-ACTION-004",
        "MSB-API-ACTION-005",
        "MSB-API-BENCH-001", "MSB-API-REQ-001", "MSB-API-REQ-002", "MSB-API-REQ-003",
      ]))
}

@Test func routerImplementsReadAPIContract() throws {
  try withFixtureRoot { fixture in
    let router = ControllerRouter(service: fixture.service, authToken: nil)
    let status = router.handle(.init(method: "GET", target: "/api/status?cache=false"))
    #expect(status.status == 200)
    let payload = try JSONSerialization.jsonObject(with: status.body) as? [String: Any]
    #expect((payload?["statuses"] as? [Any])?.count == 1)
    #expect(payload?["benchmark"] is [String: Any])
    #expect(payload?["integrations"] is [Any])
    #expect(payload?["profiles_dir"] as? String == fixture.configuration.profilesDirectory.path)
    let cached = ControllerStatusCache.load(
      from: fixture.temporary.appendingPathComponent("controller-status.json"))
    #expect(cached?.statuses.count == 1)

    let integrations = router.handle(.init(method: "GET", target: "/api/integrations"))
    #expect(integrations.status == 200)
    let root = router.handle(.init(method: "GET", target: "/"))
    #expect(root.status == 404)
    #expect(errorCode(root) == "not_found")
    let missing = router.handle(.init(method: "GET", target: "/api/missing"))
    #expect(missing.status == 404)
  }
}

@Test func routerEnforcesBearerAuthentication() throws {
  try withFixtureRoot { fixture in
    let token = "conformance-token-0000000000000001"
    let router = ControllerRouter(service: fixture.service, authToken: token)
    let denied = router.handle(.init(method: "GET", target: "/api/status"))
    #expect(denied.status == 401)
    #expect(errorCode(denied) == "unauthorized")
    let accepted = router.handle(
      .init(
        method: "GET", target: "/api/status", headers: ["Authorization": "Bearer \(token)"]
      ))
    #expect(accepted.status == 200)
  }
}

@Test func routerValidatesMutatingRequestsAndMapsErrors() throws {
  try withFixtureRoot { fixture in
    let router = ControllerRouter(service: fixture.service, authToken: nil)
    let missingField = router.handle(jsonRequest(path: "/api/start", object: [:]))
    #expect(missingField.status == 400)
    #expect(errorCode(missingField) == "invalid_request")

    let malformed = router.handle(
      .init(method: "POST", target: "/api/stop-all", body: Data("{".utf8)))
    #expect(malformed.status == 400)
    #expect(errorCode(malformed) == "invalid_json")

    let unknown = router.handle(
      jsonRequest(path: "/api/start", object: ["profile": "missing-profile"]))
    #expect(unknown.status == 404)
    #expect(errorCode(unknown) == "profile_not_found")

    let started = router.handle(jsonRequest(path: "/api/start", object: ["profile": "test"]))
    #expect(started.status == 200)
    let startedPayload = try JSONSerialization.jsonObject(with: started.body) as? [String: Any]
    #expect(startedPayload?["ok"] as? Bool == true)
  }
}

@Test func routerMapsEndpointConflicts() throws {
  try withFixtureRoot(profileBodies: [
    "alpha": fixtureProfile(port: 9001), "beta": fixtureProfile(port: 9001),
  ]) { fixture in
    let router = ControllerRouter(service: fixture.service, authToken: nil)
    let response = router.handle(jsonRequest(path: "/api/switch", object: ["profile": "alpha"]))
    #expect(response.status == 409)
    #expect(errorCode(response) == "profile_conflict")
  }
}

@Test func routerRunsNativeIntegrationAndBenchmarkActions() throws {
  let droidProfile = fixtureProfile() + "\nSYNC_TO_DROID=1\n"
  try withFixtureRoot(profileBodies: ["test": droidProfile]) { fixture in
    let settings = fixture.temporary.appendingPathComponent("settings.json")
    try "{}\n".write(to: settings, atomically: true, encoding: .utf8)
    let service = ControllerService(
      configuration: fixture.configuration,
      controllerExecutableURL: URL(fileURLWithPath: "/usr/bin/true"),
      droidSettingsURL: settings,
      statusCacheURL: fixture.temporary.appendingPathComponent("controller-status.json")
    )
    let router = ControllerRouter(service: service, authToken: nil)
    let integration = router.handle(
      jsonRequest(
        path: "/api/integrations/run", object: ["integration": "droid"]
      ))
    #expect(integration.status == 200)
    let settingsPayload =
      try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
    #expect((settingsPayload?["customModels"] as? [Any])?.count == 1)

    let benchmark = router.handle(
      jsonRequest(
        path: "/api/benchmark/start",
        object: ["profiles": ["test"], "suite": "quick", "allow_concurrent": true]
      ))
    #expect(benchmark.status == 200)
    let payload = try JSONSerialization.jsonObject(with: benchmark.body) as? [String: Any]
    #expect(payload?["ok"] as? Bool == true)
    let benchmarkStatus = payload?["benchmark"] as? [String: Any]
    #expect((benchmarkStatus?["log_path"] as? String)?.hasSuffix("benchmark.log") == true)
  }
}

@Test func httpParserEnforcesBodyLimitsAndContentLength() {
  let invalid = Data("POST /api/stop-all HTTP/1.1\r\nContent-Length: nope\r\n\r\n".utf8)
  if case .error(let status, let code, _) = HTTPParser.parse(invalid) {
    #expect(status == 400)
    #expect(code == "invalid_content_length")
  } else {
    Issue.record("expected invalid content length")
  }

  let oversized = Data("POST /api/stop-all HTTP/1.1\r\nContent-Length: 65537\r\n\r\n".utf8)
  if case .error(let status, let code, _) = HTTPParser.parse(oversized) {
    #expect(status == 413)
    #expect(code == "payload_too_large")
  } else {
    Issue.record("expected payload too large")
  }
}

private func jsonRequest(path: String, object: [String: Any]) -> ControllerHTTPRequest {
  ControllerHTTPRequest(
    method: "POST", target: path, headers: ["Content-Type": "application/json"],
    body: try! JSONSerialization.data(withJSONObject: object)
  )
}

private func errorCode(_ response: ControllerHTTPResponse) -> String? {
  ((try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any])?["error"] as? String
}
