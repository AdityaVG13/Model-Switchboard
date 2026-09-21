import Foundation
import ModelSwitchboardCore

extension HTTPParser {
  static func requestFromHeaders(
    _ headerText: String,
    data: Data,
    bodyStart: Data.Index
  ) -> HTTPParseResult {
    let lines = headerText.components(separatedBy: "\r\n")
    let first = lines.first?.split(separator: " ") ?? []
    guard first.count >= 2 else { return .error(400, "invalid_request", "invalid request line") }
    let headers = headerMap(lines.dropFirst())
    guard let contentLength = parsedContentLength(headers) else {
      return .error(400, "invalid_content_length", "invalid Content-Length")
    }
    if contentLength > ControllerConfiguration.maximumBodyBytes {
      return .error(413, "payload_too_large", "JSON payload too large")
    }
    guard let body = bodySlice(data, bodyStart: bodyStart, contentLength: contentLength) else {
      return .needMore
    }
    return .request(
      ControllerHTTPRequest(
        method: String(first[0]), target: String(first[1]), headers: headers, body: body
      ))
  }
}
