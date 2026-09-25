import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    var canBenchmark: Bool {
        profile.ready
            && store.canStartBenchmarkNow
            && !store.isBenchmarkInFlight(for: profile.profile)
    }

    var benchmarkLabel: String {
        if let gatewayDisplayName {
            return "Benchmark on \(gatewayDisplayName)"
        }
        return "Benchmark"
    }

    var benchmarkUnavailableLabel: String {
        if !profile.ready {
            return "Benchmark disabled · model not ready on :\(profile.port)"
        }
        if store.benchmark?.running == true {
            return "Benchmark running\(gatewayDisplayName.map { " on \($0)" } ?? "")…"
        }
        if !store.canStartBenchmarkNow {
            return "Benchmark cooling down"
        }
        return "Benchmark unavailable"
    }
}
