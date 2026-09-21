import Foundation
import Network

extension ControllerHTTPServer {
  func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 72 * 1024) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      var next = buffer
      if let data { next.append(data) }
      applyParse(HTTPParser.parse(next), connection: connection, buffer: next, complete: complete, error: error)
    }
  }
}
