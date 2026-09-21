import Foundation

extension SwitchboardStore {
    /// Single source of truth for the refresh lifecycle and the store's ONE error
    /// slot. Replaces the parallel `isRefreshing` boolean + `lastError` /
    /// `bootstrapDiagnostic` string slots: two errors at once and
    /// stale-vs-cached-vs-blocked ambiguity are unrepresentable. A retry in
    /// flight keeps the last failure in `refreshing(held:)` so the dashboard
    /// cannot flash empty / error-free between polls.
    enum RefreshState: Equatable {
        enum HeldFailure: Equatable {
            case failed(String)
            case cached(String)
            case blocked(String)

            var message: String {
                switch self {
                case .failed(let message), .cached(let message), .blocked(let message):
                    return message
                }
            }
        }

        /// No refresh has completed yet (initial store, or after a force-update discard).
        case idle
        /// A refresh is in flight. `held` is the last failure kept on screen.
        case refreshing(held: HeldFailure? = nil)
        /// The last refresh (or successful action) completed; freshness is
        /// time-derived from `lastUpdated`.
        case refreshed
        /// The last attempt failed. `message` is user-facing; the board may still
        /// hold stale data (freshness falls back to .stale/.error by statuses).
        case failed(message: String)
        /// A refresh failed and the board is showing the cached payload. The
        /// "cached" provenance is this case - never re-derived from message text.
        case failedShowingCached(message: String)
        /// Sticky gateway-level diagnostic (e.g. tunnel down). Refresh failures
        /// must not clobber it; only a success (or a discard) clears it.
        case blocked(message: String)

        /// The user-facing message carried by any failing case, including a
        /// retry that is still in flight.
        var message: String? {
            switch self {
            case .failed(let message), .failedShowingCached(let message), .blocked(let message):
                return message
            case .refreshing(let held):
                return held?.message
            case .idle, .refreshed:
                return nil
            }
        }
    }
}
