import Foundation

extension SSHTunnelManager {
    struct FailureMatcher {
        let needles: [String]
        let message: String
        let requireAll: Bool

        func matches(_ lowered: String) -> Bool {
            if requireAll {
                return needles.allSatisfy(lowered.contains)
            }
            return needles.contains { lowered.contains($0) }
        }
    }
}
