import Foundation

extension SSHTunnelManager {
    static func looksLikeLocalPortInUse(stderrLines: [String]) -> Bool {
        let joined = stderrLines.joined(separator: "\n").lowercased()
        return joined.contains("address already in use")
            || joined.contains("bind: address already in use")
            || joined.contains("cannot bind")
    }

    static func backoffDelay(afterFailures failures: Int, jitter: Double = .random(in: 0.8...1.2)) -> TimeInterval {
        let exponent = min(max(failures, 1), 7) - 1
        let base = min(pow(2.0, Double(exponent)), maximumBackoffSeconds)
        return min(base * jitter, maximumBackoffSeconds)
    }

    /// Maps raw ssh stderr to a short remediation the dashboard can show.
    static func classifyFailure(stderrLines: [String]) -> String {
        let stderr = stderrLines.joined(separator: "\n")
        let lowered = stderr.lowercased()
        if let match = failureMatchers.first(where: { $0.matches(lowered) }) {
            return match.message
        }
        if stderr.isEmpty {
            return "SSH exited. Check the gateway's SSH settings."
        }
        let lastLine = stderrLines.last ?? "unknown error"
        return "SSH failed: \(lastLine)"
    }
}
