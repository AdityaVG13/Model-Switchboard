import SwiftUI

extension MenuBarContentView {
    var benchmarksInspector: some View {
        BenchmarksPanelView(
            benchmark: store.benchmark,
            activeBenchmarkProfiles: store.activeBenchmarkProfiles,
            cooldownEndsAt: store.benchmarkCooldownEndsAt,
            remoteSections: remoteBenchmarkSections,
            theme: theme,
            accent: accent,
            runBenchmark: {
                // Footer CTA is scoped to This Mac - remote suites are started
                // from each gateway's row/hero actions, not this inspector button.
                Task { await store.quickBenchmark() }
            }
        )
    }
}
