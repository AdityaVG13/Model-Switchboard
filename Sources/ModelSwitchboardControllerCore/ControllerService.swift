import Darwin
import Foundation
import ModelSwitchboardCore

public final class ControllerService: @unchecked Sendable {
  public let configuration: ControllerConfiguration
  public let profiles: ProfileRepository
  let controllerExecutableURL: URL
  let droidSettingsURL: URL
  let statusCacheURL: URL
  public lazy var benchmarks = BenchmarkService(service: self)
  public lazy var doctor = DoctorService(service: self)

  private let mutationLock = NSRecursiveLock()
  private let fileManager: FileManager
  private var watchdogSuppressedUntil = Date.distantPast

  public init(
    configuration: ControllerConfiguration,
    fileManager: FileManager = .default,
    controllerExecutableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
    droidSettingsURL: URL? = nil,
    statusCacheURL: URL? = nil
  ) {
    self.configuration = configuration
    self.fileManager = fileManager
    self.controllerExecutableURL = controllerExecutableURL
    self.droidSettingsURL =
      droidSettingsURL
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".factory/settings.json")
    self.statusCacheURL =
      statusCacheURL
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Caches/io.modelswitchboard/controller-status.json")
    profiles = ProfileRepository(
      directory: configuration.profilesDirectory, fileManager: fileManager)
  }

  public func statusPayload(selected: [String]? = nil) throws -> ControllerStatusPayload {
    let loaded = try profiles.load()
    let conflicts = profiles.conflicts(in: loaded)
    let names = selected ?? loaded.keys.sorted()
    let statuses = try names.map { name -> ModelProfileStatus in
      guard let profile = loaded[name] else { throw ControllerError.profileNotFound(name) }
      return status(for: profile, allowPortFallback: conflicts[name] == nil)
    }
    return ControllerStatusPayload(
      statuses: statuses,
      benchmark: benchmarks.status(),
      integrations: integrationStatus(),
      profilesDirectory: configuration.profilesDirectory.path,
      controllerRoot: configuration.root.path
    )
  }

  public func actionResponse() throws -> ControllerActionResponse {
    let payload = try statusPayload()
    return ControllerActionResponse(
      ok: true,
      statuses: payload.statuses,
      benchmark: payload.benchmark,
      integrations: payload.integrations,
      profilesDirectory: payload.profilesDirectory,
      controllerRoot: payload.controllerRoot,
      error: nil
    )
  }

  public func status(for profile: ControllerProfile, allowPortFallback: Bool = true)
    -> ModelProfileStatus
  {
    let health = probeHealth(profile)
    var pid = readPID(profile.name)
    if let current = pid, !ProcessRunner.processIsAlive(current) {
      try? fileManager.removeItem(at: pidFile(profile.name))
      pid = nil
    }
    if pid == nil, allowPortFallback, let listener = listenerPID(port: profile.endpointPort),
      processMatches(listener, profile: profile)
    {
      pid = listener
    }
    let spec = profile.runtimeSpec
    return ModelProfileStatus(
      profile: profile.name,
      displayName: profile.displayName,
      runtime: profile.runtime,
      runtimeLabel: spec.label,
      runtimeTags: profile.runtimeTags,
      launchMode: spec.launchMode,
      host: profile.endpointHost,
      port: profile.endpointPort,
      baseURL: profile.baseURL,
      requestModel: profile.requestModel,
      serverModelID: profile.serverModelID,
      pid: pid,
      running: ProcessRunner.processIsAlive(pid),
      ready: health.ready,
      serverIDs: health.serverIDs,
      rssMB: rssMB(pid),
      command: processCommand(pid),
      logPath: profile.logPath
    )
  }

  public func start(_ name: String) throws {
    try withMutationLock {
      let loaded = try profiles.load()
      guard loaded[name] != nil else { throw ControllerError.profileNotFound(name) }
      try profiles.ensureUnique(name, action: "start", profiles: loaded)
      var environment = ProcessInfo.processInfo.environment
      environment["MODEL_PROFILE"] = name
      environment.merge(loaded[name]?.values ?? [:]) { _, new in new }
      environment["MODEL_SWITCHBOARD_PROFILE_LOADED"] = "1"
      environment["MODEL_SWITCHBOARD_CONTROLLER_BIN"] = controllerExecutableURL.path
      _ = try ProcessRunner.run(
        "/bin/bash",
        [configuration.startScript.path],
        environment: environment,
        currentDirectory: configuration.root
      )
    }
  }

  public func stop(_ name: String) throws {
    try withMutationLock {
      suppressWatchdog()
      clearActiveProfile(ifMatching: name)
      let profile = try profiles.profile(named: name)
      let currentStatus = status(for: profile)
      var stopError: Error?
      if let command = profile["STOP_COMMAND"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !command.isEmpty
      {
        do {
          var environment = ProcessInfo.processInfo.environment
          environment.merge(profile.values) { _, new in new }
          _ = try ProcessRunner.run(
            "/bin/bash", ["-lc", command], environment: environment,
            currentDirectory: profileWorkingDirectory(profile)
          )
        } catch {
          stopError = error
        }
      }
      if profile["STOP_COMMAND_ONLY"] != "1" {
        terminateProfileProcesses(profile, primaryPID: currentStatus.pid)
        guard waitUntilStopped(profile, primaryPID: currentStatus.pid) else {
          throw ControllerError.operationFailed(
            "failed to stop \(name): endpoint or process is still alive")
        }
      }
      try? fileManager.removeItem(at: pidFile(name))
      if let stopError {
        throw ControllerError.operationFailed("STOP_COMMAND failed for \(name): \(stopError)")
      }
    }
  }

  public func restart(_ name: String) throws {
    try withMutationLock {
      let loaded = try profiles.load()
      guard loaded[name] != nil else { throw ControllerError.profileNotFound(name) }
      try profiles.ensureUnique(name, action: "restart", profiles: loaded)
      try stop(name)
      try start(name)
    }
  }

  public func switchProfile(_ name: String) throws {
    try withMutationLock {
      let loaded = try profiles.load()
      guard loaded[name] != nil else { throw ControllerError.profileNotFound(name) }
      try profiles.ensureUnique(name, action: "activate", profiles: loaded)
      for item in try statusPayload().statuses where item.profile != name && item.running {
        try stop(item.profile)
      }
      try start(name)
      try fileManager.createDirectory(
        at: configuration.runDirectory, withIntermediateDirectories: true)
      try "\(name)\n".write(to: configuration.activeProfileFile, atomically: true, encoding: .utf8)
    }
  }

  public func stopAll() throws {
    try withMutationLock {
      if let benchmarkPID = readPID("benchmark") {
        ProcessRunner.terminate(benchmarkPID)
        try? fileManager.removeItem(at: pidFile("benchmark"))
      }
      var failures: [String] = []
      for name in try profiles.load().keys.sorted() {
        do { try stop(name) } catch { failures.append("\(name): \(error)") }
      }
      var environment = ProcessInfo.processInfo.environment
      environment["MODEL_SWITCHBOARD_RUN_DIR"] = configuration.runDirectory.path
      _ = try? ProcessRunner.run(
        "/bin/bash", [configuration.stopAllScript.path], environment: environment,
        currentDirectory: configuration.root, check: false
      )
      if !failures.isEmpty {
        throw ControllerError.operationFailed(
          "Failed to stop profiles: \(failures.joined(separator: "; "))")
      }
    }
  }

  public func integrationStatus() -> [ControllerIntegration] {
    let droidExists =
      fileManager.fileExists(atPath: droidSettingsURL.path)
      || (try? ProcessRunner.run("/usr/bin/which", ["droid"], check: false).status) == 0
    guard droidExists else { return [] }
    return [
      ControllerIntegration(
        id: "droid",
        displayName: "Factory Droid",
        kind: "model_registry",
        capabilities: ["sync"],
        syncLabel: "Sync Droid",
        description: "Sync managed local profiles into Factory Droid custom model settings."
      )
    ]
  }

  public func runIntegration(_ id: String, action: String) throws {
    guard id == "droid", action == "sync" else {
      throw ControllerError.unsupported("Unsupported integration action: \(id):\(action)")
    }
    try DroidSyncService(
      configuration: configuration, profiles: profiles, settingsURL: droidSettingsURL
    ).sync()
  }

  public func writeStatusCache(_ payload: ControllerStatusPayload) throws {
    let directory = statusCacheURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let destination = statusCacheURL
    let temporary = directory.appendingPathComponent("controller-status.tmp")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(CachedControllerStatusPayload(payload: payload)).write(
      to: temporary, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
    } else {
      try fileManager.moveItem(at: temporary, to: destination)
    }
  }

  public func watchdogTick() {
    guard Date() >= watchdogSuppressedUntil,
      let name = try? String(contentsOf: configuration.activeProfileFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
    else { return }
    guard let profile = try? profiles.profile(named: name) else {
      try? fileManager.removeItem(at: configuration.activeProfileFile)
      return
    }
    let current = status(for: profile)
    if !current.ready && !current.running { try? start(name) }
  }

  public func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(
      queue: DispatchQueue(label: "io.modelswitchboard.controller.watchdog"))
    timer.schedule(deadline: .now() + 30, repeating: 30)
    timer.setEventHandler { [weak self] in self?.watchdogTick() }
    timer.resume()
    _watchdogTimer = timer
  }

  private var _watchdogTimer: DispatchSourceTimer?

  private func withMutationLock<T>(_ operation: () throws -> T) rethrows -> T {
    mutationLock.lock()
    defer { mutationLock.unlock() }
    return try operation()
  }

  private func pidFile(_ name: String) -> URL {
    configuration.runDirectory.appendingPathComponent("\(name).pid")
  }

  private func readPID(_ name: String) -> Int? {
    guard let value = try? String(contentsOf: pidFile(name), encoding: .utf8) else { return nil }
    return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private func listenerPID(port: String) -> Int? {
    guard !port.isEmpty,
      let result = try? ProcessRunner.run(
        "/usr/sbin/lsof", ["-tiTCP:\(port)", "-sTCP:LISTEN"], check: false)
    else { return nil }
    return result.stdout.split(whereSeparator: \.isNewline).compactMap { Int($0) }.first
  }

  private func processCommand(_ pid: Int?) -> String? {
    guard let pid,
      let result = try? ProcessRunner.run(
        "/bin/ps", ["-o", "command=", "-p", String(pid)], check: false)
    else { return nil }
    let command = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return command.isEmpty ? nil : command
  }

  private func rssMB(_ pid: Int?) -> Double? {
    guard let pid,
      let result = try? ProcessRunner.run(
        "/bin/ps", ["-o", "rss=", "-p", String(pid)], check: false),
      let rss = Double(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return nil }
    return (rss / 1024 * 10).rounded() / 10
  }

  private func processMatches(_ pid: Int, profile: ControllerProfile) -> Bool {
    guard let command = processCommand(pid)?.lowercased() else { return false }
    let markers = [
      profile.name, profile["MODEL_ALIAS"], profile.requestModel, profile.serverModelID,
      profile["MODEL_PATH"], profile["MODEL_DIR"], profile["MODEL_FILE"], profile["MODEL_REPO"],
    ]
    return markers.compactMap { $0?.lowercased() }.contains {
      $0.count >= 4 && command.contains($0)
    }
  }

  private func probeHealth(_ profile: ControllerProfile) -> (ready: Bool, serverIDs: [String]) {
    guard profile.healthcheckMode != "disabled", let url = URL(string: profile.healthcheckURL),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else { return (false, []) }
    let remoteAllowed = ["1", "true", "yes"].contains(
      ProcessInfo.processInfo.environment["ALLOW_REMOTE_HEALTHCHECK"]?.lowercased() ?? "")
    guard remoteAllowed || ControllerConfiguration.isLoopback(url.host ?? "") else {
      return (false, [])
    }
    guard
      let result = try? ProcessRunner.run(
        "/usr/bin/curl",
        [
          "--fail", "--silent", "--show-error", "--max-time", "1.5", "--header",
          "Accept: application/json", url.absoluteString,
        ]
      )
    else { return (false, []) }
    if profile.healthcheckMode == "http-200" { return (true, []) }
    guard let data = result.stdout.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let entries = object["data"] as? [[String: Any]]
    else { return (false, []) }
    let ids = entries.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
    let expected = profile["HEALTHCHECK_EXPECT_ID"] ?? profile.serverModelID
    return (expected.isEmpty ? !ids.isEmpty : ids.contains(expected), ids)
  }

  private func profileWorkingDirectory(_ profile: ControllerProfile) -> URL? {
    guard let raw = profile["WORKING_DIRECTORY"] ?? profile["WORKDIR"], !raw.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
  }

  private func terminateProfileProcesses(_ profile: ControllerProfile, primaryPID: Int?) {
    if let primaryPID { ProcessRunner.terminate(primaryPID) }
    if let listener = listenerPID(port: profile.endpointPort), listener != primaryPID,
      processMatches(listener, profile: profile)
    {
      ProcessRunner.terminate(listener)
    }
  }

  private func waitUntilStopped(_ profile: ControllerProfile, primaryPID: Int?) -> Bool {
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
      let listener = listenerPID(port: profile.endpointPort)
      let listenerAlive =
        listener.map { $0 == primaryPID || processMatches($0, profile: profile) } ?? false
      if !ProcessRunner.processIsAlive(primaryPID), !listenerAlive { return true }
      Thread.sleep(forTimeInterval: 0.2)
    }
    return false
  }

  private func suppressWatchdog() { watchdogSuppressedUntil = Date().addingTimeInterval(45) }

  private func clearActiveProfile(ifMatching name: String) {
    guard
      let current = try? String(contentsOf: configuration.activeProfileFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), current == name
    else { return }
    try? fileManager.removeItem(at: configuration.activeProfileFile)
  }
}
