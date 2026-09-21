import Foundation

extension RemoteAgentVersion {
    /// Numeric dotted compare (`1.1.2` < `1.1.3` < `1.2`). Non-numeric
    /// segments sort as 0 so a junk remote version still counts as stale.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        comparePadded(components(lhs), components(rhs))
    }

    static func comparePadded(_ left: [Int], _ right: [Int]) -> ComparisonResult {
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = component(left, index)
            let b = component(right, index)
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func component(_ values: [Int], _ index: Int) -> Int {
        index < values.count ? values[index] : 0
    }

    static func components(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }
}
