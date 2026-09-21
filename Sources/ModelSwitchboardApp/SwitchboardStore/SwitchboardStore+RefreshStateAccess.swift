import Foundation

extension SwitchboardStore.RefreshState {
    var isInFlight: Bool {
        if case .refreshing = self { true } else { false }
    }

    var isBlocked: Bool {
        switch self {
        case .blocked:
            return true
        case .refreshing(.blocked):
            return true
        default:
            return false
        }
    }

    /// Start a refresh without dropping the last failure from the UI.
    func beginningRefresh() -> SwitchboardStore.RefreshState {
        switch self {
        case .failed(let message):
            return .refreshing(held: .failed(message))
        case .failedShowingCached(let message):
            return .refreshing(held: .cached(message))
        case .blocked(let message):
            return .refreshing(held: .blocked(message))
        case .refreshing(let held):
            return .refreshing(held: held)
        case .idle, .refreshed:
            return .refreshing(held: nil)
        }
    }
}
