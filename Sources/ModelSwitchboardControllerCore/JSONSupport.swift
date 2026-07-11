import Foundation

public enum JSONSupport {
  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  public static func data<T: Encodable>(_ value: T) throws -> Data {
    try encoder.encode(value)
  }

  public static func data(_ object: Any) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }

  public static func object(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ControllerError.operationFailed("JSON body must be an object")
    }
    return object
  }
}
