import Foundation
import ModelSwitchboardCore

enum HTTPParser {
  static func parse(_ data: Data) -> HTTPParseResult {
    let delimiter = Data("\r\n\r\n".utf8)
    guard let range = data.range(of: delimiter) else {
      return data.count > 16 * 1024
        ? .error(400, "invalid_request", "request headers too large") : .needMore
    }
    return parseEnvelope(data, headerEnd: range.lowerBound, bodyStart: range.upperBound)
  }

  static func parseEnvelope(
    _ data: Data,
    headerEnd: Data.Index,
    bodyStart: Data.Index
  ) -> HTTPParseResult {
    guard let headerText = String(data: data[..<headerEnd], encoding: .utf8) else {
      return .error(400, "invalid_request", "request headers must be UTF-8")
    }
    return requestFromHeaders(headerText, data: data, bodyStart: bodyStart)
  }
}
