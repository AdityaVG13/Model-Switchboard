import Darwin
import Foundation

extension UserFacingControllerError {
    static func mapPOSIX(_ entry: NSError, isLocal: Bool) -> String? {
        switch entry.code {
        case Int(ECONNREFUSED):
            return connectionRefusedCopy(isLocal: isLocal)
        case Int(ENETUNREACH), Int(EHOSTUNREACH):
            return "No network route to the gateway."
        case Int(ECONNRESET), Int(ENOTCONN):
            return "Connection to the gateway was lost."
        default:
            return nil
        }
    }
}
