import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var canReopenLastActive: Bool {
        features.supportsBenchmarks &&
        !lastActiveProfiles.isEmpty &&
        !pendingGlobalActions.contains("reopen-last") &&
        !statuses.contains(where: \.running) &&
        pendingProfileActions.isEmpty
    }

    var benchmarkCooldownRemaining: TimeInterval {
        guard let lastBenchmarkStartedAt else { return 0 }
        let remaining = Constants.benchmarkCooldownSeconds - Date().timeIntervalSince(lastBenchmarkStartedAt)
        return max(0, remaining)
    }

    var benchmarkCooldownEndsAt: Date? {
        guard let lastBenchmarkStartedAt else { return nil }
        return lastBenchmarkStartedAt.addingTimeInterval(Constants.benchmarkCooldownSeconds)
    }

    var canStartBenchmarkNow: Bool {
        features.supportsBenchmarks &&
        benchmark?.running != true &&
        benchmarkCooldownRemaining <= 0
    }

    var benchmarkCooldownLabel: String? {
        let remaining = benchmarkCooldownRemaining
        guard remaining > 0 else { return nil }
        let seconds = Int(remaining.rounded(.up))
        let minutesPart = seconds / 60
        let secondsPart = seconds % 60
        if minutesPart > 0 {
            return "\(minutesPart)m \(secondsPart)s"
        }
        return "\(secondsPart)s"
    }

    func markBenchmarkStarted() {
        let now = Date()
        lastBenchmarkStartedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Constants.benchmarkCooldownKey)
    }
}
