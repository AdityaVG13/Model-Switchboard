import Foundation
import Network

public final class ControllerHTTPServer: @unchecked Sendable {
  let configuration: ControllerConfiguration
  let router: ControllerRouter
  let queue = DispatchQueue(label: "io.modelswitchboard.controller.http")
  var listener: NWListener?

  public init(configuration: ControllerConfiguration, router: ControllerRouter) {
    self.configuration = configuration
    self.router = router
  }

  public func stop() {
    listener?.cancel()
    listener = nil
  }

  func accept(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(connection, buffer: Data())
  }
}
