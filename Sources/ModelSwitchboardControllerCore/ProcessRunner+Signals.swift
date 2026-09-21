import Darwin
import Foundation
import ModelSwitchboardCore

extension ProcessRunner {
  public static func processIsAlive(_ pid: Int?) -> Bool {
    guard let pid, pid > 0 else { return false }
    return kill(pid_t(pid), 0) == 0 || errno == EPERM
  }

  public static func signalProcessTree(_ pid: Int, signal: Int32) {
    let processGroup = getpgid(pid_t(pid))
    if processGroup > 0, processGroup != getpgrp() {
      _ = killpg(processGroup, signal)
    }
    if let children = try? run("/usr/bin/pgrep", ["-P", String(pid)], check: false) {
      for child in children.stdout.split(whereSeparator: \.isNewline).compactMap({ Int($0) })
        .reversed()
      {
        signalProcessTree(child, signal: signal)
      }
    }
    _ = kill(pid_t(pid), signal)
  }

  public static func terminate(_ pid: Int, timeout: TimeInterval = 12) {
    signalProcessTree(pid, signal: SIGTERM)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, processIsAlive(pid) {
      Thread.sleep(forTimeInterval: 0.2)
    }
    if processIsAlive(pid) {
      signalProcessTree(pid, signal: SIGKILL)
    }
  }
}
