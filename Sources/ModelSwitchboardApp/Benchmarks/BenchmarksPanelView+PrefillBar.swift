import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func prefillBar(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.cellBg)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent)
                    .frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(height: 6)
        .frame(maxWidth: .infinity)
    }
}
