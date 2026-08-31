import Foundation

/// Screen-share privacy: mask host-identifying strings in read-only UI.
///
/// When "Hide hosts and addresses" is enabled in Settings, hostnames, tailnet
/// names, IP addresses, SSH user@host destinations, and the host part of
/// endpoint URLs render as a fixed-width mask. Names, ports, models, and
/// metrics stay visible so the dashboard still demos well. Editing fields in
/// Settings are form inputs, not read-only surfaces, and stay legible.
public enum DisplayPrivacy {
    public static let defaultsKey = "modelswitchboard.hideHostInfo"

    public static var isHostInfoHidden: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Fixed-width mask: leaks neither length nor characters.
    static let mask = "••••"

    /// Mask a bare hostname, IPv4/IPv6, tailnet name, or `user@host`.
    /// Ports and paths are the caller's business and survive masking when
    /// they pass them separately (see `url` / `hostPort`).
    public static func host(_ value: String?, hidden: Bool = isHostInfoHidden) -> String {
        guard hidden, let value, !value.isEmpty else { return value ?? "" }
        return mask
    }

    /// Mask the host inside `host:port`, keeping the port.
    public static func hostPort(_ host: String?, port: String, hidden: Bool = isHostInfoHidden) -> String {
        guard hidden, let host, !host.isEmpty else { return "\(host ?? ""):\(port)" }
        return "\(mask):\(port)"
    }

    /// Mask the host inside an http(s) URL, keeping scheme, port, and path:
    /// `http://••••:8050/v1`. Unparseable input masks whole. URLComponents is
    /// used read-only: mutating `host` punycodes non-ASCII, so the string is
    /// rebuilt from parsed parts instead.
    public static func url(_ value: String?, hidden: Bool = isHostInfoHidden) -> String {
        guard hidden, let value, !value.isEmpty else { return value ?? "" }
        guard let components = URLComponents(string: value), let scheme = components.scheme else {
            return mask
        }
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

    /// Mask the SSH/URL summary line shown on gateway rows:
    /// `ssh user@host -p 22 → 127.0.0.1:8877` keeps only the loopback target
    /// (that one is every install's default and identifies nothing).
    public static func connectionSummary(_ value: String, hidden: Bool = isHostInfoHidden) -> String {
        guard hidden else { return value }
        guard let arrowRange = value.range(of: " → ") else {
            if value.lowercased().hasPrefix("http") {
                return url(value, hidden: true)
            }
            return mask
        }
        let target = String(value[arrowRange.upperBound...])
        return "\(mask) → \(target)"
    }
}
