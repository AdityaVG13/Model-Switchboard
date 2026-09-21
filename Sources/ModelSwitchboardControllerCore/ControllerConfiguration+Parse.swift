import Foundation
import ModelSwitchboardCore

extension ControllerConfiguration {
  static func applyArgument(
    _ argument: String,
    iterator: inout IndexingIterator<[String]>,
    into parsed: inout ParsedArguments
  ) throws {
    switch argument {
    case "--root":
      parsed.root = URL(fileURLWithPath: expandedPath(try requiredValue("--root", iterator: &iterator)))
    case "--profiles-dir":
      parsed.profilesDirectory = URL(
        fileURLWithPath: expandedPath(try requiredValue("--profiles-dir", iterator: &iterator)),
        isDirectory: true)
    case "--host":
      parsed.host = try requiredValue("--host", iterator: &iterator)
    case "--unsafe-bind":
      parsed.host = try requiredValue("--unsafe-bind", iterator: &iterator)
      parsed.unsafeBind = true
    case "--port":
      parsed.port = try parsePort(iterator: &iterator)
    case "--auth-token":
      parsed.token = try requiredValue("--auth-token", iterator: &iterator)
    case "--auth-token-file":
      parsed.token = try readAuthTokenFile(iterator: &iterator)
    default:
      return
    }
  }

  static func parsePort(iterator: inout IndexingIterator<[String]>) throws -> UInt16 {
    guard let parsedPort = UInt16(try requiredValue("--port", iterator: &iterator)) else {
      throw ControllerError.usage("invalid value for --port")
    }
    return parsedPort
  }

  static func readAuthTokenFile(iterator: inout IndexingIterator<[String]>) throws -> String {
    try String(
      contentsOfFile: expandedPath(try requiredValue("--auth-token-file", iterator: &iterator)),
      encoding: .utf8
    ).trimmed
  }

  static func expandedPath(_ raw: String) -> String {
    NSString(string: raw).expandingTildeInPath
  }

  static func requiredValue(_ flag: String, iterator: inout IndexingIterator<[String]>) throws -> String {
    guard let value = iterator.next() else {
      throw ControllerError.usage(flag == "--port" ? "invalid value for --port" : "missing value for \(flag)")
    }
    return value
  }
}
