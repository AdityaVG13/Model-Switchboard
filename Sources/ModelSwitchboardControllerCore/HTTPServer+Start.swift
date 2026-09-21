import Foundation
import Network

extension ControllerHTTPServer {
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
}
