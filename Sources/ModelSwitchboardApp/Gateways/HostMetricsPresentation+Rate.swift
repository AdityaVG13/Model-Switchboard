import Foundation
import ModelSwitchboardCore

extension HostMetricsPresentation {
    /// Tailnet state for the Remote Hosts card: short label + detail.
    static func tailnetLabel(_ metrics: HostMetricsPayload?) -> (label: String, detail: String?)? {
        guard let tailnet = metrics?.tailscale else { return nil }
        let warnings = tailnet.health
        if tailnet.online == false {
            return (label: "TAILNET OFF", detail: warnings.first)
        }
        if !warnings.isEmpty {
            return (label: "TAILNET WARN", detail: warnings.first)
        }
        if tailnet.online == true {
            return (label: "TAILNET OK", detail: tailnet.ipv4)
        }
        return nil
    }

    /// Compact tok/s label for a running row: "42.3 tok/s" or nil.
    static func servingRateLabel(_ status: ModelProfileStatus) -> String? {
        guard let tokS = status.serving?.tokS, tokS > 0 else { return nil }
        if tokS >= 100 {
            return String(format: "%.0f tok/s", tokS)
        }
        return String(format: "%.1f tok/s", tokS)
    }

    static func percentLabel(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int(value.rounded()))%"
    }
}
