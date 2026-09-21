import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// A pending global action. Benchmarks carry their target as data instead of
    /// encoding it in a `bench-<profile>` string that callers prefix-sniff.
    enum GlobalAction: Equatable, Hashable {
        case stopAll
        case reopenLastActive
        case benchmarkAll
        case benchmarkSelected
        case benchmark(profile: String)

        var isBenchmark: Bool {
            switch self {
            case .benchmarkAll, .benchmarkSelected, .benchmark: true
            case .stopAll, .reopenLastActive: false
            }
        }
    }

    enum ProfileBadgeState: Equatable {
        case pending(String)
        case running
        case stale
        case notRunning
    }
}
