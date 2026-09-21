import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    @ViewBuilder
    var benchmarkMenuItems: some View {
        if canBenchmark {
            Button(benchmarkLabel) {
                onOpenBenchmarks?()
                Task { await store.quickBenchmark([profile.profile]) }
            }
        } else {
            Button(benchmarkUnavailableLabel) {}
                .disabled(true)
        }
    }
}
