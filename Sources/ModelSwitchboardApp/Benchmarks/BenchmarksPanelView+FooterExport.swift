import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    var exportCSVButton: some View {
        Button {
            guard let latest = benchmark?.latest else { return }
            BenchmarkCSVExport.presentSavePanel(for: latest) { notice in
                exportNotice = notice
            }
        } label: {
            Text("Export This Mac CSV")
                .font(.system(size: 11.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .foregroundStyle(canExport ? theme.btnFg : theme.faint)
        .disabled(!canExport)
        .help("Exports the latest This Mac benchmark run. Remote results stay on their gateway sections.")
    }

    var canTriggerBenchmark: Bool {
        benchmark?.running != true && benchmarkCooldownLabel == nil
    }

    var canExport: Bool {
        !(benchmark?.latest?.rows.isEmpty ?? true) && benchmark?.running != true
    }
}
