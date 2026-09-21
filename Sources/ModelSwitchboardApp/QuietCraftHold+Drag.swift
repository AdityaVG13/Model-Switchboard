import SwiftUI

extension HoldToConfirmTextButton {
    var holdDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !disabled, !isBusy else { return }
                // Scrubbing away cancels - mirrors cancel-by-drag-away.
                if hypot(value.translation.width, value.translation.height) > 28 {
                    cancelHold()
                    return
                }
                beginHoldIfNeeded()
            }
            .onEnded { _ in
                cancelHold()
            }
    }
}
