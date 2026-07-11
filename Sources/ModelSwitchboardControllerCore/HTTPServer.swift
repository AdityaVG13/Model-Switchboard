import Foundation
import Network

public final class ControllerHTTPServer: @unchecked Sendable {
  private let configuration: ControllerConfiguration
  private let router: ControllerRouter
  private let queue = DispatchQueue(label: "io.modelswitchboard.controller.http")
  private var listener: NWListener?

  public init(configuration: ControllerConfiguration, router: ControllerRouter) {
    self.configuration = configuration
    self.router = router
  }

  public func start() throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(
      host: NWEndpoint.Host(configuration.host),
      port: NWEndpoint.Port(rawValue: configuration.port)!
    )
    let listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    listener.stateUpdateHandler = { state in
      if case .failed(let error) = state {
        FileHandle.standardError.write(Data("controller listener failed: \(error)\n".utf8))
      }
    }
    self.listener = listener
    listener.start(queue: queue)
  }

  public func stop() {
    listener?.cancel()
    listener = nil
  }

  private func accept(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(connection, buffer: Data())
  }

  private func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 72 * 1024) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      var next = buffer
      if let data { next.append(data) }
      switch HTTPParser.parse(next) {
      case .request(let request):
        send(router.handle(request), connection: connection)
      case .needMore where !complete && error == nil:
        receive(connection, buffer: next)
      case .error(let status, let code, let message):
        let body =
          (try? JSONSupport.data(["ok": false, "error": code, "message": message])) ?? Data()
        send(ControllerHTTPResponse(status: status, body: body), connection: connection)
      default:
        connection.cancel()
      }
    }
  }

  private func send(_ response: ControllerHTTPResponse, connection: NWConnection) {
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

enum HTTPParseResult {
  case request(ControllerHTTPRequest)
  case needMore
  case error(Int, String, String)
}

enum HTTPParser {
  static func parse(_ data: Data) -> HTTPParseResult {
    let delimiter = Data("\r\n\r\n".utf8)
    guard let range = data.range(of: delimiter) else {
      return data.count > 16 * 1024
        ? .error(400, "invalid_request", "request headers too large") : .needMore
    }
    guard let headerText = String(data: data[..<range.lowerBound], encoding: .utf8) else {
      return .error(400, "invalid_request", "request headers must be UTF-8")
    }
    let lines = headerText.components(separatedBy: "\r\n")
    let first = lines.first?.split(separator: " ") ?? []
    guard first.count >= 2 else { return .error(400, "invalid_request", "invalid request line") }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...])
        .trimmingCharacters(in: .whitespaces)
    }
    let contentLength: Int
    if let raw = headers["content-length"] {
      guard let parsed = Int(raw), parsed >= 0 else {
        return .error(400, "invalid_content_length", "invalid Content-Length")
      }
      contentLength = parsed
    } else {
      contentLength = 0
    }
    if contentLength > ControllerConfiguration.maximumBodyBytes {
      return .error(413, "payload_too_large", "JSON payload too large")
    }
    let bodyStart = range.upperBound
    guard data.count >= bodyStart + contentLength else { return .needMore }
    let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
    return .request(
      ControllerHTTPRequest(
        method: String(first[0]), target: String(first[1]), headers: headers, body: body
      ))
  }
}
