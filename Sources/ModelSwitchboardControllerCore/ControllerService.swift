import Darwin
import Foundation
import ModelSwitchboardCore

public final class ControllerService: @unchecked Sendable {
  public internal(set) var configuration: ControllerConfiguration
  public internal(set) var profiles: ProfileRepository
  let controllerExecutableURL: URL
  let droidSettingsURL: URL
  let statusCacheURL: URL
  public lazy var benchmarks = BenchmarkService(service: self)
  public lazy var doctor = DoctorService(service: self)

  let mutationLock = NSRecursiveLock()
  let fileManager: FileManager
  var watchdogSuppressedUntil = Date.distantPast
  var watchdogTimer: DispatchSourceTimer?

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

  func withMutationLock<T>(_ operation: () throws -> T) rethrows -> T {
    mutationLock.lock()
    defer { mutationLock.unlock() }
    return try operation()
  }
}
