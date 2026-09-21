import Foundation

extension DisplayPrivacy {
    /// Mask the SSH/URL summary line shown on gateway rows:
    /// `ssh user@host -p 22 → 127.0.0.1:8877` keeps only the loopback target
    /// (that one is every install's default and identifies nothing).
    public static func connectionSummary(_ value: String, hidden: Bool = isHostInfoHidden) -> String {
        guard hidden else { return value }
        if value.lowercased().hasPrefix("http") {
            return url(value, hidden: true)
        }
        guard value.hasPrefix("ssh "), let arrowRange = value.range(of: " → ") else {
            return mask
        }
        let target = String(value[arrowRange.upperBound...])
        return "\(mask) → \(target)"
    }
}
