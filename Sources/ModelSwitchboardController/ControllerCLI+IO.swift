import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
  static func runJSONStrings() throws {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    for item in try JSONSupport.stringArray(fromJSON: data) {
      print(item)
    }
  }

  static func runOpenAIModelsContains(_ arguments: [String]) throws {
    let expected = option("--id", in: arguments)
    guard let expected, !expected.isEmpty else {
      throw ControllerError.usage("missing --id")
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    exit(JSONSupport.openaiModelsContains(id: expected, json: data) ? 0 : 1)
  }

  static func printJSON<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try JSONSupport.data(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  static func printJSONObject(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSupport.data(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  static func encodableObjects<T: Encodable>(_ values: [T]) throws -> [Any] {
    try JSONSerialization.jsonObject(with: JSONSupport.data(values)) as? [Any] ?? []
  }
}
