import Foundation

/// Canonical loopback controller endpoint shared by the app, widget, and scripts.
public enum ControllerEndpointDefaults: Sendable {
    public static let host = "127.0.0.1"
    public static let port: UInt16 = 8877
    public static let baseURLString = "http://\(host):\(port)"
    public static let baseURLUserDefaultsKey = "controllerBaseURL"
}
