import Foundation
import ModelSwitchboardCore

extension ControllerConfiguration {
  static func parseArguments(_ arguments: [String]) throws -> ParsedArguments {
    let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Application Support/ModelSwitchboard/Controller", isDirectory: true)
    var parsed = ParsedArguments(
      root: defaultRoot,
      host: defaultHost,
      port: UInt16(defaultPort),
      unsafeBind: false
    )
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
      try applyArgument(argument, iterator: &iterator, into: &parsed)
    }
    return parsed
  }
}
