import Foundation
import ModelSwitchboardCore

extension BenchmarkMetricFormatting {
    static func suiteLabel(_ suite: String?) -> String {
        guard let suite = suite.nonEmptyTrimmed else {
            return "Unknown"
        }
        let normalized = suite.lowercased()
        if normalized == "quick" { return "Default" }
        return normalized
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }
}
