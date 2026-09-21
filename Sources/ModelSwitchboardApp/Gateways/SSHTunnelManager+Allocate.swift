import Darwin
import Foundation
import ModelSwitchboardCore

extension SSHTunnelManager {
    static func allocateLoopbackPort() -> UInt16 {
        withLoopbackStreamSocket { socketFD in
            guard bindLoopback(socketFD, port: 0) else { return nil }
            var assigned = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &assigned) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(socketFD, $0, &length)
                }
            }
            guard nameResult == 0 else { return nil }
            return UInt16(bigEndian: assigned.sin_port)
        } ?? 0
    }
}
