import SwiftUI

extension HoldToConfirmTextButton {
    func beginHoldIfNeeded() {
        guard holdTask == nil else { return }
        isHolding = true
        progress = 0
        let duration = reduceMotion ? min(holdDuration, 0.6) : holdDuration
        holdTask = Task { @MainActor in
            let steps = 28
            let step = duration / Double(steps)
            for i in 1...steps {
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .linear(duration: step)) {
                    progress = CGFloat(i) / CGFloat(steps)
                }
            }
            guard !Task.isCancelled else { return }
            progress = 0
            isHolding = false
            holdTask = nil
            action()
        }
    }

    func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            progress = 0
        }
    }
}
