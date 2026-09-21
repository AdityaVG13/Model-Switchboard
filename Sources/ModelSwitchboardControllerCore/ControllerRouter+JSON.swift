import Foundation

extension ControllerRouter {
  func requestObject(_ request: ControllerHTTPRequest) throws -> [String: Any] {
    if request.body.isEmpty { return [:] }
    do {
      guard let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
      else {
        throw ControllerError.usage("request body must be a JSON object")
      }
      return object
    } catch let error as ControllerError {
      throw error
    } catch {
      throw RouterError.invalidJSON
    }
  }

  func requiredString(_ payload: [String: Any], key: String) throws -> String {
    guard let value = payload[key] as? String, !value.isEmpty else {
      throw ControllerError.usage("missing required string field: \(key)")
    }
    return value
  }

  func optionalStrings(_ payload: [String: Any], key: String) throws -> [String]? {
    guard let value = payload[key] else { return nil }
    guard let strings = value as? [String] else {
      throw ControllerError.usage("\(key) must be a list of strings")
    }
    return strings
  }
}
