import Foundation

public extension Array where Element == ModelProfileStatus {
    /// Rows the dashboard, widget, and actions may show or mutate.
    /// Discovery/listening listeners stay out of this set.
    var boardVisible: [ModelProfileStatus] {
        filter(\.isBoardVisible)
    }

    func sortedForDisplay() -> [ModelProfileStatus] {
        sorted(by: ModelProfileStatus.compareForDisplay)
    }
}
