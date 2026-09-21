import SwiftUI

/// Hold-to-confirm for destructive actions (Stop Everything / hero Stop / Remove gateway).
/// Press and hold ~1.4s to fire; release or scrub away cancels with a fast snap-back.
struct HoldToConfirmTextButton: View {
    enum Chrome {
        /// Compact footer text control.
        case plain
        /// Fills available width - hero Stop / settings destructive.
        case filled(background: Color, foreground: Color)
    }

    let title: String
    var color: Color
    var isBusy: Bool = false
    var disabled: Bool = false
    var holdDuration: TimeInterval = 1.4
    /// Extra context for the tooltip (e.g. what Stop Everything will stop).
    var helpDetail: String? = nil
    var chrome: Chrome = .plain
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var progress: CGFloat = 0
    @State var holdTask: Task<Void, Never>?
    @State var isHolding = false

    var helpText: String {
        if disabled {
            return helpDetail ?? "Unavailable"
        }
        if let helpDetail, !helpDetail.isEmpty {
            return "Hold to confirm. \(helpDetail)"
        }
        return "Hold to confirm \(title)"
    }

    var labelWeight: Font.Weight {
        if case .filled = chrome { return .semibold }
        return .regular
    }
}
