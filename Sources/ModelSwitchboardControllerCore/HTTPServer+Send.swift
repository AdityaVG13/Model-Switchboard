import Foundation
import Network

extension ControllerHTTPServer {
  func applyParse(
    _ result: HTTPParseResult,
    connection: NWConnection,
    buffer: Data,
    complete: Bool,
    error: Error?
  ) {
    switch result {
    case .request(let request):
      send(router.handle(request), connection: connection)
    case .needMore where !complete && error == nil:
      receive(connection, buffer: buffer)
    case .error(let status, let code, let message):
      let body =
        (try? JSONSupport.data(["error": code, "message": message])) ?? Data()
      send(ControllerHTTPResponse(status: status, body: body), connection: connection)
    default:
      connection.cancel()
    }
  }

  func send(_ response: ControllerHTTPResponse, connection: NWConnection) {
    let reason =
      [
        200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict",
        413: "Payload Too Large", 500: "Internal Server Error",
      ][response.status] ?? "OK"
    var headers = response.headers
    headers["Content-Length"] = String(response.body.count)
    headers["Connection"] = "close"
    var message = Data("HTTP/1.1 \(response.status) \(reason)\r\n".utf8)
    for key in headers.keys.sorted() { message.append(Data("\(key): \(headers[key]!)\r\n".utf8)) }
    message.append(Data("\r\n".utf8))
    message.append(response.body)
    connection.send(content: message, completion: .contentProcessed { _ in connection.cancel() })
  }
}
