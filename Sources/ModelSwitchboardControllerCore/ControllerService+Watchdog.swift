import Darwin
import Foundation
import ModelSwitchboardCore

extension ControllerService {
  public func watchdogTick() {
    guard Date() >= watchdogSuppressedUntil,
      let name = try? String(contentsOf: configuration.activeProfileFile, encoding: .utf8)
        .nonEmptyTrimmed
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
    watchdogTimer = timer
  }
}
