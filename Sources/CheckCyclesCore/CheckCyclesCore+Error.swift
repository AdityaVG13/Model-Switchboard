import Foundation

public enum CheckCyclesError: Error, CustomStringConvertible {
    case commandFailed(String, String)
    case invalidSPMDescribe
    case missingProjectYML(String)

    public var description: String {
        switch self {
        case .commandFailed(let cmd, let stderr):
            return "\(cmd) failed: \(stderr)"
        case .invalidSPMDescribe:
            return "invalid swift package describe JSON"
        case .missingProjectYML(let path):
            return "missing required file: \(path)"
        }
    }
}
