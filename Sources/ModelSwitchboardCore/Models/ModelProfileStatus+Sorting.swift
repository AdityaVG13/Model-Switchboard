import Foundation

public extension Array where Element == ModelProfileStatus {
    func sortedForDisplay() -> [ModelProfileStatus] {
        sorted(by: ModelProfileStatus.compareForDisplay)
    }
}
