import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func prefillSection(_ cases: [BenchmarkPrefillCase]) -> some View {
        let maxTTFT = max(cases.compactMap(\.ttftMS).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 0) {
            Text("PREFILL SCALING \u{00b7} TTFT BY CONTEXT")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.faint)
                .padding(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            ForEach(Array(cases.enumerated()), id: \.offset) { _, benchCase in
                prefillRow(benchCase, maxTTFT: maxTTFT)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 10))
    }
}
