import Foundation

public extension ModelProfileStatus {
    static func compareForDisplay(_ lhs: Self, _ rhs: Self) -> Bool {
        if let preferred = preferActive(lhs, rhs) { return preferred }
        if let ranked = compareAscending(lhs.displayHostRank, rhs.displayHostRank) { return ranked }
        if let host = compareLocalized(lhs.normalizedDisplayHost, rhs.normalizedDisplayHost) { return host }
        if let port = compareAscending(lhs.displayPortRank, rhs.displayPortRank) { return port }
        if let name = compareLocalized(lhs.displayName, rhs.displayName) { return name }
        return lhs.profile.localizedCaseInsensitiveCompare(rhs.profile) == .orderedAscending
    }

    static func preferActive(_ lhs: Self, _ rhs: Self) -> Bool? {
        if lhs.running != rhs.running {
            return lhs.running && !rhs.running
        }
        if lhs.running && lhs.ready != rhs.ready {
            return lhs.ready && !rhs.ready
        }
        return nil
    }

    static func compareAscending<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool? {
        lhs == rhs ? nil : lhs < rhs
    }

    static func compareLocalized(_ lhs: String, _ rhs: String) -> Bool? {
        let order = lhs.localizedCaseInsensitiveCompare(rhs)
        return order == .orderedSame ? nil : order == .orderedAscending
    }
}
