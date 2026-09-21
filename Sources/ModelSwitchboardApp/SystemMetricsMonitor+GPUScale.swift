import Foundation
import IOKit
import Darwin

extension SystemMetricsMonitor {
    func normalizePercentage(_ value: AnyObject) -> Double? {
        if let number = value as? NSNumber {
            return normalizePercentage(number.doubleValue)
        }
        if let text = value as? String, let parsed = Double(text) {
            return normalizePercentage(parsed)
        }
        return nil
    }

    func normalizePercentage(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return scaledPercentage(value)
    }

    func scaledPercentage(_ value: Double) -> Double? {
        if value >= 0 && value <= 1 {
            return value * 100
        }
        if value >= 0 && value <= 100 {
            return value
        }
        if value > 100 && value <= 10_000 {
            return min(max(value / 100, 0), 100)
        }
        return nil
    }
}
