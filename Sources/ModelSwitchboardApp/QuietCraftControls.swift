import SwiftUI

/// Quiet Craft press feedback: subtle scale on press, skipped under Reduce Motion.
struct QuietCraftPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
    }
}

/// Hold-to-confirm for destructive actions (Stop Everything / hero Stop / Remove gateway).
/// Press and hold ~1.4s to fire; release or scrub away cancels with a fast snap-back.
struct HoldToConfirmTextButton: View {
    enum Chrome {
        /// Compact footer text control.
        case plain
        /// Fills available width — hero Stop / settings destructive.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?
    @State private var isHolding = false

    private var helpText: String {
        if disabled {
            return helpDetail ?? "Unavailable"
        }
        if let helpDetail, !helpDetail.isEmpty {
            return "Hold to confirm. \(helpDetail)"
        }
        return "Hold to confirm \(title)"
    }

    private var labelWeight: Font.Weight {
        if case .filled = chrome { return .semibold }
        return .regular
    }

    var body: some View {
        HStack(spacing: 4) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(title)
                .font(.system(size: 11.5, weight: labelWeight))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .padding(.horizontal, fillsWidth ? 0 : 4)
        .padding(.vertical, fillsWidth ? 6 : 2)
        .frame(minHeight: fillsWidth ? nil : 24)
        .background { progressBackground }
        .clipShape(RoundedRectangle(cornerRadius: fillsWidth ? 7 : 4, style: .continuous))
        .contentShape(Rectangle())
        .foregroundStyle(labelColor)
        .opacity(disabled && !isBusy ? 0.4 : 1)
        .scaleEffect(isHolding && !reduceMotion ? 0.97 : 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isHolding
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !disabled, !isBusy else { return }
                    // Scrubbing away cancels — mirrors cancel-by-drag-away.
                    if hypot(value.translation.width, value.translation.height) > 28 {
                        cancelHold()
                        return
                    }
                    beginHoldIfNeeded()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
        .disabled(isBusy || disabled)
        .accessibilityLabel(title)
        .accessibilityHint(
            disabled
                ? (helpDetail ?? "Unavailable")
                : "Hold to confirm, or activate with VoiceOver to confirm immediately"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            guard !disabled, !isBusy else { return }
            action()
        }
        .help(helpText)
        .onDisappear { cancelHold() }
    }

    private var fillsWidth: Bool {
        if case .filled = chrome { return true }
        return false
    }

    private var labelColor: Color {
        switch chrome {
        case .plain:
            return color
        case .filled(_, let foreground):
            return foreground
        }
    }

    @ViewBuilder
    private var progressBackground: some View {
        switch chrome {
        case .plain:
            GeometryReader { geo in
                color.opacity(0.22)
                    .frame(width: max(0, geo.size.width * progress))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        case .filled(let background, _):
            ZStack(alignment: .leading) {
                background
                GeometryReader { geo in
                    color.opacity(0.35)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
        }
    }

    private func beginHoldIfNeeded() {
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

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            progress = 0
        }
    }
}
