import Foundation

/// Bundled remote-agent version and stale comparison.
///
/// `bundled` must match `AGENT_VERSION` in `RemoteAgent/model_switchboard_agent.py`.
/// The Mac app is ahead of a host whenever that host reports an older (or
/// missing) version; clicking the gateway badge pushes this build's agent.
public enum RemoteAgentVersion {
    public static let bundled = "1.1.3"

    /// True when host metrics prove the remote agent is older than this app.
    /// No metrics yet is not stale (unknown). An agent that lacks the metrics
    /// route (`unsupported`) is treated as stale -- that endpoint shipped
    /// with the versioned agent.
    public static func isRemoteStale(
        metrics: HostMetricsPayload?,
        unsupported: Bool
    ) -> Bool {
        if unsupported { return true }
        guard let metrics else { return false }
        return isOlderThanBundled(metrics.agentVersion)
    }

    public static func isOlderThanBundled(_ remote: String?) -> Bool {
        let trimmed = remote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return true }
        return compare(trimmed, bundled) == .orderedAscending
    }

    /// Numeric dotted compare (`1.1.2` < `1.1.3` < `1.2`). Non-numeric
    /// segments sort as 0 so a junk remote version still counts as stale.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }
}
