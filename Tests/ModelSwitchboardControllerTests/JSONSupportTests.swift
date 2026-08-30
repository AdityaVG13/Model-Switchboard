import Foundation
import Testing

@testable import ModelSwitchboardControllerCore

@Test func jsonStringsExpandsArrayLikeJqTostring() throws {
  let data = Data(#"[ "--port", 8080, true, false, null, {"k":1} ]"#.utf8)
  let items = try JSONSupport.stringArray(fromJSON: data)
  #expect(items[0] == "--port")
  #expect(items[1] == "8080")
  #expect(items[2] == "true")
  #expect(items[3] == "false")
  #expect(items[4] == "null")
  #expect(items[5].contains("k"))
}

@Test func jsonStringsRejectsNonArray() {
  #expect(throws: ControllerError.self) {
    _ = try JSONSupport.stringArray(fromJSON: Data(#"{"a":1}"#.utf8))
  }
}

@Test func openaiModelsContainsMatchesIdAndRejectsInvalidJSON() {
  let json = Data(#"{"data":[{"id":"llama-3"},{"id":"other"}]}"#.utf8)
  #expect(JSONSupport.openaiModelsContains(id: "llama-3", json: json))
  #expect(!JSONSupport.openaiModelsContains(id: "missing", json: json))
  #expect(!JSONSupport.openaiModelsContains(id: "llama-3", json: Data("not-json".utf8)))
}

@Test func startModelMacAppendJSONArgsDiesOnControllerFailure() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let text = try String(
    contentsOf: root.appendingPathComponent("Controller/start-model-mac.sh"), encoding: .utf8)
  #expect(!text.contains("jq"))
  #expect(text.contains("if ! parsed="))
  #expect(text.contains("SERVER_ARGS_JSON must be a JSON array"))
}
