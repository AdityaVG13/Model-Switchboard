import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func applyFailedRefresh(_ error: Error, previousState: RefreshState) {
        if isBenignCancellation(error) { return }
        if applyCachedRefreshIfPossible(error, previousState: previousState) { return }
        if previousState.isBlocked { return }
        noteRecoveringFrom(error)
        refreshState = .failed(
            message: Self.userFacingErrorDescription(for: error, isLocal: gateway.isLocal)
        )
    }

    func applyCachedRefreshIfPossible(_ error: Error, previousState: RefreshState) -> Bool {
        guard statuses.isEmpty, let cached = cachedStateLoader() else { return false }
        apply(payload: cached.payload)
        lastUpdated = cached.cachedAt
        // A sticky gateway diagnostic (blocked before this refresh) keeps
        // the slot: it outranks the cache-fallback copy and must never be
        // re-derived from message text. Otherwise the fallback is
        // recorded as the structured .failedShowingCached provenance.
        if previousState.isBlocked { return true }
        noteRecoveringFrom(error)
        refreshState = .failedShowingCached(message: "Controller unavailable. Showing cached state.")
        return true
    }
}
