import SwiftUI
import ModelSwitchboardCore

extension ActiveProfileHeroView {
    var heroActions: some View {
        HStack(spacing: 6) {
            HoldToConfirmTextButton(
                title: "Stop",
                color: DashboardTheme.stopRed,
                isBusy: isBusy,
                disabled: isBusy,
                helpDetail: isBusy ? "Busy" : "Stop \(profile.displayName)",
                chrome: .filled(background: theme.btnStrongBg, foreground: theme.btnStrongFg)
            ) {
                Task { await store.stop(profile.profile) }
            }
            actionButton("Restart", disabled: isBusy) {
                Task { await store.restart(profile.profile) }
            }
            actionButton("Benchmark", disabled: isBusy || !canBenchmark) {
                onOpenBenchmarks?()
                Task { await store.quickBenchmark([profile.profile]) }
            }
            .help(benchmarkHelp)
        }
    }
}
