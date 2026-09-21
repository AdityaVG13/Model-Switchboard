import Foundation
import ModelSwitchboardCore

extension ControllerService {
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
}
