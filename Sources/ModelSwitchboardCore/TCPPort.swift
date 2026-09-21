import Foundation

/// Shared TCP port range used by pairing links, forwards, and draft validation.
public enum TCPPort {
    public static let validRange = 1...65535

    public static func isValid(_ port: Int) -> Bool {
        validRange.contains(port)
    }
}
