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
}
