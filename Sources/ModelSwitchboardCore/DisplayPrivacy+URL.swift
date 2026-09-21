import Foundation

extension DisplayPrivacy {
    /// Mask the host inside an http(s) URL, keeping scheme, port, and path:
    /// `http://••••:8050/v1`. Unparseable input masks whole. URLComponents is
    /// used read-only: mutating `host` punycodes non-ASCII, so the string is
    /// rebuilt from parsed parts instead.
    public static func url(_ value: String?, hidden: Bool = isHostInfoHidden) -> String {
        guard hidden, let value, !value.isEmpty else { return value ?? "" }
        guard let components = URLComponents(string: value), let scheme = components.scheme else {
            return mask
        }
        return maskedURL(scheme: scheme, components: components)
    }

    static func maskedURL(scheme: String, components: URLComponents) -> String {
        var rebuilt = "\(scheme)://\(mask)"
        if let port = components.port {
            rebuilt += ":\(port)"
        }
        if !components.path.isEmpty {
            rebuilt += components.path
        }
        if let query = components.query {
            rebuilt += "?\(query)"
        }
        return rebuilt
    }
}
