import Foundation

/// Bundled remote-agent version and stale comparison.
///
/// `bundled` must match `AGENT_VERSION` in `RemoteAgent/model_switchboard_agent.py`.
/// The Mac app is ahead of a host whenever that host reports an older (or
/// missing) version; clicking the gateway badge pushes this build's agent.
public enum RemoteAgentVersion {
    public static let bundled = "2.0.0"

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
        guard let trimmed = remote.nonEmptyTrimmed else { return true }
        return compare(trimmed, bundled) == .orderedAscending
    }
}
