import Darwin
import Foundation
import ModelSwitchboardCore

extension SSHTunnelManager {
    static func canConnectLoopback(port: UInt16) -> Bool {
        withLoopbackStreamSocket { socketFD in
            var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
            setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var address = loopbackAddress(port: port)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            return result == 0
        } ?? false
    }

    /// True when nothing is currently bound to `127.0.0.1:port`.
    static func isLoopbackPortFree(_ port: UInt16) -> Bool {
        guard port != 0 else { return false }
        return withLoopbackStreamSocket { bindLoopback($0, port: port) } ?? false
    }
}
