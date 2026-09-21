import Foundation
import ModelSwitchboardCore

enum BenchmarkMetricFormatting {
    static func milliseconds(_ value: Double?) -> String {
        formatted(value, digits: 0)
    }

    static func tokensPerSecond(_ value: Double?) -> String {
        formatted(value, digits: 1)
    }

    static func megabytes(_ value: Double?) -> String {
        formatted(value, digits: 0)
    }

    static func formatted(_ value: Double?, digits: Int) -> String {
        guard let value else { return "-" }
        return String(format: "%.\(digits)f", value)
    }
}
