import SwiftUI
import ModelSwitchboardCore

extension ActiveProfileHeroView {
    var canBenchmark: Bool {
        store.features.supportsBenchmarks
            && profile.ready
            && store.canStartBenchmarkNow
            && !store.isBenchmarkInFlight(for: profile.profile)
    }

    var benchmarkHelp: String {
        switch context {
        case .local:
            return "Run a quick benchmark on This Mac."
        case .remote(let name):
            return remoteBenchmarkHelp(gatewayName: name)
        }
    }

    var showsURLSelection: Bool {
        switch context {
        case .local:
            return true
        case .remote:
            return reachableEndpointURL != nil
        }
    }

    func remoteBenchmarkHelp(gatewayName: String) -> String {
        if !profile.ready {
            return "Benchmark disabled: model on :\(profile.port) is not ready yet."
        }
        if !store.canStartBenchmarkNow {
            return "Benchmark cooling down or already running on \(gatewayName)."
        }
        return "Run a quick benchmark on \(gatewayName) via the remote agent (uses the model on that host)."
    }
}
