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

/// Hold-to-confirm for destructive footer actions (Stop Everything / Stop All).
/// Press and hold ~1.4s to fire; release cancels with a fast snap-back.
struct HoldToConfirmTextButton: View {
    let title: String
    var color: Color
    var isBusy: Bool = false
    var disabled: Bool = false
    var holdDuration: TimeInterval = 1.4
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?
    @State private var isHolding = false

    var body: some View {
        HStack(spacing: 4) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(title)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            GeometryReader { geo in
                color.opacity(0.22)
                    .frame(width: max(0, geo.size.width * progress))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .foregroundStyle(color)
        .opacity(disabled && !isBusy ? 0.4 : 1)
        .scaleEffect(isHolding && !reduceMotion ? 0.97 : 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isHolding
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !disabled, !isBusy else { return }
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
                ? "Nothing is running"
                : "Hold to confirm"
        )
        .accessibilityAddTraits(.isButton)
        .help(disabled ? "Nothing is running" : "Hold to confirm \(title)")
        .onDisappear { cancelHold() }
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
