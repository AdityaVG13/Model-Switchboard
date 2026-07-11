import Foundation
import Testing

@testable import ModelSwitchboardControllerCore

@Test func nativeControllerConfigurationEnforcesBindSecurity() throws {
  let root = URL(fileURLWithPath: "/tmp/controller")
  let loopback = try ControllerConfiguration(root: root)
  #expect(loopback.host == "127.0.0.1")
  #expect(loopback.port == 8877)
  #expect(throws: ControllerError.self) {
    try ControllerConfiguration(root: root, host: "0.0.0.0")
  }
  #expect(throws: ControllerError.self) {
    try ControllerConfiguration(root: root, host: "0.0.0.0", unsafeBind: true)
  }
  let secured = try ControllerConfiguration(
    root: root, host: "0.0.0.0", authToken: String(repeating: "x", count: 32), unsafeBind: true
  )
  #expect(secured.authToken?.count == 32)
}

@Test func profileRepositoryParsesDeclarativeProfilesAndDetectsConflicts() throws {
  try withFixtureRoot(profileBodies: [
    "alpha": fixtureProfile(displayName: "Alpha", port: 9001),
    "beta": fixtureProfile(displayName: "Beta", port: 9001),
  ]) { fixture in
    let repository = ProfileRepository(directory: fixture.configuration.profilesDirectory)
    let profiles = try repository.load()
    #expect(profiles["alpha"]?.displayName == "Alpha")
    #expect(profiles["alpha"]?.baseURL == "http://127.0.0.1:9001/v1")
    #expect(repository.conflicts(in: profiles).keys.sorted() == ["alpha", "beta"])
  }
}

@Test func profileRepositoryRejectsShellStatements() throws {
  try withFixtureRoot(profileBodies: [
    "bad": "DISPLAY_NAME=Bad\nREQUEST_MODEL=test\nPORT=9001\necho unsafe\n"
  ]) { fixture in
    let repository = ProfileRepository(directory: fixture.configuration.profilesDirectory)
    #expect(throws: ControllerError.self) { try repository.load() }
  }
}

@Test func nativeProfileParserReplaysFuzzCorpusWithoutExecutingLiterals() throws {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let corpus = repositoryRoot.appendingPathComponent(
    "Controller/tests/fuzz/corpus", isDirectory: true)
  let repository = ProfileRepository(directory: corpus)
  let marker = URL(fileURLWithPath: "/tmp/modelswitchboard-fuzz-should-not-exist")
  try? FileManager.default.removeItem(at: marker)
  let safe = try repository.parseValues(file: corpus.appendingPathComponent("profile_env/safe.env"))
  #expect(safe["INLINE_COMMENT"] == "value")
  let injection = try repository.parseValues(
    file: corpus.appendingPathComponent("profile_env/injection_literals.env"))
  #expect(injection["DISPLAY_NAME"]?.contains("$(touch") == true)
  #expect(!FileManager.default.fileExists(atPath: marker.path))
  #expect(throws: ControllerError.self) {
    try repository.parseValues(
      file: corpus.appendingPathComponent("profile_env/invalid-key.invalid.env"))
  }
  #expect(throws: ControllerError.self) {
    try repository.parseValues(
      file: corpus.appendingPathComponent("profile_env/invalid-shell.invalid.env"))
  }
  let nested = try repository.parseValues(
    file: corpus.appendingPathComponent("profile_json/nested.json"))
  #expect(nested["SYNC_TO_DROID"] == "1")
  #expect(nested["SERVER_ARGS_JSON"]?.hasPrefix("[") == true)
  #expect(throws: ControllerError.self) {
    try repository.parseValues(
      file: corpus.appendingPathComponent("profile_json/invalid-key.invalid.json"))
  }
  #expect(throws: Error.self) {
    try repository.parseValues(
      file: corpus.appendingPathComponent("profile_json/scalar.invalid.json"))
  }
}

struct ControllerFixture {
  let temporary: URL
  let configuration: ControllerConfiguration
  let service: ControllerService
}

func withFixtureRoot(
  profileBodies: [String: String] = ["test": fixtureProfile()],
  _ operation: (ControllerFixture) throws -> Void
) throws {
  let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
    "model-switchboard-tests-\(UUID().uuidString)")
  let root = temporary.appendingPathComponent("Controller", isDirectory: true)
  let profiles = root.appendingPathComponent("model-profiles", isDirectory: true)
  try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
  for (name, body) in profileBodies {
    try body.write(
      to: profiles.appendingPathComponent("\(name).env"), atomically: true, encoding: .utf8)
  }
  for script in ["start-model-mac.sh", "stop-all-models.sh"] {
    let url = root.appendingPathComponent(script)
    try "#!/bin/bash\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }
  let configuration = try ControllerConfiguration(root: root)
  defer { try? FileManager.default.removeItem(at: temporary) }
  try operation(
    ControllerFixture(
      temporary: temporary,
      configuration: configuration,
      service: ControllerService(
        configuration: configuration,
        statusCacheURL: temporary.appendingPathComponent("controller-status.json")
      )
    ))
}

func fixtureProfile(displayName: String = "Test", port: Int = 9001) -> String {
  """
  DISPLAY_NAME="\(displayName)"
  RUNTIME=external
  PORT=\(port)
  REQUEST_MODEL=test-model
  HEALTHCHECK_MODE=disabled
  LAUNCH_MODE=external
  """
}
