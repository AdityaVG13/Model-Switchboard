import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    enum StatusFreshness: Equatable {
        case fresh
        case stale
        case cached
        case error
    }

    /// A pending per-profile action. The case is the identity; `label` is the
    /// display token shown in the UI (kept byte-stable: hero copy uppercases it).
    enum ProfileAction: String, Equatable, Hashable {
        case activating, starting, stopping, restarting

        var label: String {
            switch self {
            case .activating: "ACTIVATING"
            case .starting: "STARTING"
            case .stopping: "STOPPING"
            case .restarting: "RESTARTING"
            }
        }

        /// User-facing action name for error copy ("Start", "Stop", …).
        var displayName: String {
            switch self {
            case .activating: "Activate"
            case .starting: "Start"
            case .stopping: "Stop"
            case .restarting: "Restart"
            }
        }
    }
}
