import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var remoteBenchmarkSections: [GatewayBenchmarkSection] {
        hub.enabledRemoteRuntimes.map { runtime in
            GatewayBenchmarkSection(
                id: runtime.id,
                name: runtime.name,
                benchmark: runtime.store.benchmark,
                activeBenchmarkProfiles: runtime.store.activeBenchmarkProfiles,
                cooldownEndsAt: runtime.store.benchmarkCooldownEndsAt
            )
        }
    }
}
