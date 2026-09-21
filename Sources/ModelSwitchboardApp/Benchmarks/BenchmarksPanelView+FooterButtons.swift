import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    var panelFooter: some View {
        HStack {
            Button {
                runBenchmark()
            } label: {
                Text(runButtonTitle)
                    .font(.system(size: 11.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietCraftPressStyle())
            .foregroundStyle(canTriggerBenchmark ? theme.btnFg : theme.faint)
            .disabled(!canTriggerBenchmark)

            Spacer()

            exportCSVButton
        }
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
    }
}
