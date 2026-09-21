import Foundation
import ModelSwitchboardCore

extension GatewayRuntime {
    func sshReachableEndpointURL(for status: ModelProfileStatus) -> String? {
        // Forwards may remap remote N → a different local port when N is
        // already taken (second gateway, local server, etc.).
        guard let remotePort = Int(status.port),
              let localPort = forwardedPorts[remotePort],
              var components = URLComponents(string: status.baseURL)
        else { return nil }
        components.host = "127.0.0.1"
        components.port = localPort
        return components.url?.absoluteString
    }
}
