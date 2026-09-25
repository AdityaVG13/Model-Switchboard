import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var benchmarkCooldownRemaining: TimeInterval {
        guard let lastBenchmarkStartedAt else { return 0 }
        return max(0, Constants.benchmarkCooldownSeconds - Date().timeIntervalSince(lastBenchmarkStartedAt))
    }

    var benchmarkCooldownEndsAt: Date? {
        lastBenchmarkStartedAt?.addingTimeInterval(Constants.benchmarkCooldownSeconds)
    }

    var canStartBenchmarkNow: Bool {
        benchmark?.running != true && benchmarkCooldownRemaining <= 0
    }

    var benchmarkCooldownLabel: String? {
        DurationFormatting.compactCountdown(remaining: benchmarkCooldownRemaining)
    }

    func markBenchmarkStarted() {
        let now = Date()
        lastBenchmarkStartedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: benchmarkCooldownDefaultsKey)
    }
}
