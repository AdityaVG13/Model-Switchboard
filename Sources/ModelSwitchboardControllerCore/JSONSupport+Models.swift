import Foundation

extension JSONSupport {
  /// jq `-r '.[] | tostring'` for `SERVER_ARGS_JSON` (LaunchAgent-safe; no jq).
  public static func stringArray(fromJSON data: Data) throws -> [String] {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let array = object as? [Any] else {
      throw ControllerError.invalidConfiguration("SERVER_ARGS_JSON must be a JSON array")
    }
    return try array.map(jsonToString)
  }

  /// True when `/v1/models` JSON lists `id` in `.data[]`. Invalid JSON is a miss.
  /// Empty `expected` never matches (identity must be explicit; use a sentinel id).
  public static func openaiModelsContains(id expected: String, json data: Data) -> Bool {
    guard !expected.isEmpty,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = object["data"] as? [Any]
    else { return false }
    return items.contains { item in
      guard let row = item as? [String: Any] else { return false }
      return (row["id"] as? String) == expected
    }
  }

  static func jsonToString(_ value: Any) throws -> String {
    if value is NSNull { return "null" }
    if let string = value as? String { return string }
    if let bool = boolValue(value) { return bool ? "true" : "false" }
    if let number = value as? NSNumber { return number.stringValue }
    guard JSONSerialization.isValidJSONObject(value) else {
      return String(describing: value)
    }
    let data = try JSONSerialization.data(withJSONObject: value)
    return String(data: data, encoding: .utf8) ?? ""
  }
}
