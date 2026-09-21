import Foundation

public extension ModelProfileStatus {
    /// The four legal combinations of the wire `running`/`ready` booleans,
    /// named so display code switches once instead of re-deriving ad hoc.
    enum Lifecycle: Equatable, Sendable {
        case stopped        // !running && !ready
        case starting       // running && !ready  - owned process, endpoint pending
        case running        // running && ready
        case readyUnowned   // !running && ready  - foreign listener answers health

        public var isActive: Bool { self != .stopped }
        public var isRunning: Bool { self == .running }
    }

    var lifecycle: Lifecycle {
        switch (running, ready) {
        case (true, true): return .running
        case (true, false): return .starting
        case (false, true): return .readyUnowned
        case (false, false): return .stopped
        }
    }
}
