import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func metricColumn(_ value: String, unit: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(emphasized ? accent : theme.label)
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(theme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
