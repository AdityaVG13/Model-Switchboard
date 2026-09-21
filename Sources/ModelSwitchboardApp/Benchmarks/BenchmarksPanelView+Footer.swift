import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    var needsCountdownTick: Bool {
        if cooldownEndsAt != nil { return true }
        if benchmark?.running == true { return true }
        return remoteSections.contains { $0.benchmark?.running == true || $0.cooldownEndsAt != nil }
    }

    var runButtonTitle: String {
        if benchmark?.running == true { return "Benchmark Running\u{2026}" }
        if let suite = benchmark?.latest?.suite, !suite.isEmpty {
            return "Run Suite on This Mac: \(BenchmarkMetricFormatting.suiteLabel(suite).lowercased())"
        }
        return "Run Benchmark on This Mac"
    }

    var benchmarkCooldownLabel: String? {
        guard let cooldownEndsAt else { return nil }
        return DurationFormatting.compactCountdown(endsAt: cooldownEndsAt, relativeTo: now)
    }

    var activeRunLabel: String {
        if activeBenchmarkProfiles.isEmpty {
            return "Benchmark is running for all profiles."
        }
        if activeBenchmarkProfiles.count == 1, let only = activeBenchmarkProfiles.first {
            return "Benchmark is running for profile: \(only)."
        }
        return "Benchmark is running for \(activeBenchmarkProfiles.count) selected profiles."
    }
}
