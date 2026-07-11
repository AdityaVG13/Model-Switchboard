import Foundation
import Testing

@testable import ModelSwitchboardControllerCore

@Test func serviceReportsProfilesAndRunsLifecycleScripts() throws {
  try withFixtureRoot { fixture in
    let payload = try fixture.service.statusPayload()
    #expect(payload.statuses.count == 1)
    #expect(payload.statuses[0].profile == "test")
    #expect(payload.statuses[0].running == false)
    try fixture.service.start("test")
    try fixture.service.restart("test")
    try fixture.service.stop("test")
    try fixture.service.stopAll()
  }
}

@Test func doctorProducesNativeContract() throws {
  try withFixtureRoot { fixture in
    let report = try fixture.service.doctor.report()
    #expect(report.schemaVersion == "1")
    #expect(report.doctorContractVersion == "1.0")
    #expect(report.profiles.count == 1)
    #expect(report.controller.reachable)
  }
}

@Test func nativeDoctorFixesAndUndoesMissingProfilesDirectorySafely() throws {
  try withFixtureRoot(profileBodies: [:]) { fixture in
    try FileManager.default.removeItem(at: fixture.configuration.profilesDirectory)
    let preview = try fixture.service.doctor.applyFixes(dryRun: true, runID: "preview")
    #expect(preview["actions_taken"] as? Int == 1)
    #expect(!FileManager.default.fileExists(atPath: fixture.configuration.profilesDirectory.path))
    let applied = try fixture.service.doctor.applyFixes(dryRun: false, runID: "native-fix")
    #expect(applied["actions_taken"] as? Int == 1)
    #expect(FileManager.default.fileExists(atPath: fixture.configuration.profilesDirectory.path))
    let undone = try fixture.service.doctor.undo("native-fix")
    #expect((undone["undone"] as? [Any])?.count == 1)
    #expect(!FileManager.default.fileExists(atPath: fixture.configuration.profilesDirectory.path))
    #expect(throws: ControllerError.self) { try fixture.service.doctor.undo("../../unsafe") }
  }
}

@Test func benchmarkWorkerWritesNativeArtifactsForEmptyProfileSet() throws {
  try withFixtureRoot(profileBodies: [:]) { fixture in
    try fixture.service.benchmarks.runWorker(
      selectedNames: nil, suite: "quick", allowConcurrent: false, keepRunning: false
    )
    let latest = fixture.configuration.benchmarkResultsDirectory.appendingPathComponent(
      "latest.json")
    #expect(FileManager.default.fileExists(atPath: latest.path))
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: latest)) as? [String: Any]
    #expect(payload?["suite"] as? String == "quick")
    #expect((payload?["benchmarks"] as? [Any])?.isEmpty == true)
  }
}

@Test func nativeHTTPServerPassesRealServiceE2E() throws {
  try withFixtureRoot { fixture in
    let port = UInt16.random(in: 20_000...50_000)
    let token = "native-controller-token-000000000001"
    let configuration = try ControllerConfiguration(
      root: fixture.configuration.root,
      port: port,
      authToken: token
    )
    let service = ControllerService(
      configuration: configuration,
      statusCacheURL: fixture.temporary.appendingPathComponent("controller-status.json")
    )
    let server = ControllerHTTPServer(
      configuration: configuration,
      router: ControllerRouter(service: service, authToken: token)
    )
    try server.start()
    defer { server.stop() }
    let url = "http://127.0.0.1:\(port)/api/status"
    var unauthorized: ProcessResult?
    for _ in 0..<30 {
      unauthorized = try ProcessRunner.run(
        "/usr/bin/curl", ["--silent", "--output", "/dev/null", "--write-out", "%{http_code}", url],
        check: false
      )
      if unauthorized?.stdout == "401" { break }
      Thread.sleep(forTimeInterval: 0.05)
    }
    #expect(unauthorized?.stdout == "401")
    let authorized = try ProcessRunner.run(
      "/usr/bin/curl", ["--fail", "--silent", "--header", "Authorization: Bearer \(token)", url]
    )
    let payload =
      try JSONSerialization.jsonObject(with: Data(authorized.stdout.utf8)) as? [String: Any]
    #expect((payload?["statuses"] as? [Any])?.count == 1)
  }
}
