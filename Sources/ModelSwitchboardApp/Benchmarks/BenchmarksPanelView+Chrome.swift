import SwiftUI

extension BenchmarksPanelView {
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.faint)
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 0, trailing: 14))
    }

    func noticeText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 6, leading: 14, bottom: 0, trailing: 14))
    }
}

/// Only ticks the countdown clock while a run or cooldown is active.
struct BenchmarkTickModifier: ViewModifier {
    let needsTick: Bool
    @Binding var now: Date

    func body(content: Content) -> some View {
        if needsTick {
            content
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
                    now = tick
                }
        } else {
            content
        }
    }
}
