import Darwin
import Foundation
import ModelSwitchboardCore

extension ControllerServiceManager {
    /// Runs `body` off the main actor. The reachability probe blocks up to
    /// 200ms in connect(2); polling it inline would freeze the UI.
    static func offMainQueue(_ body: @escaping @Sendable () -> Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: body())
            }
        }
    }

    /// Awaitable reachability check that never blocks the main actor.
    func isControllerReachable() async -> Bool {
        await Self.offMainQueue { Self.controllerReachableSync() }
    }

    nonisolated static func controllerReachableSync() -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = ControllerEndpointDefaults.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(ControllerEndpointDefaults.host))

        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
