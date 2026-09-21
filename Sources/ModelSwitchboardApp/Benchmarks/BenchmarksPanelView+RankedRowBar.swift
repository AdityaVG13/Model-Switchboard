import SwiftUI
import ModelSwitchboardCore

extension BenchmarksPanelView {
    func rankedRowBar(fraction: Double, isTop: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.cellBg)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isTop ? accent : theme.sparkStroke)
                    .frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(width: 70, height: 5)
    }
}
