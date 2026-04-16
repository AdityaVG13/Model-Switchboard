import SwiftUI

struct LeverSwitchIcon: View {
    let hasReadyModels: Bool
    let hasRunningModels: Bool
    var size: CGFloat = 18

    private var accent: Color {
        if hasReadyModels { return .green }
        if hasRunningModels { return .orange }
        return .red
    }

    private var leverRotation: Angle {
        if hasReadyModels { return .degrees(-28) }
        if hasRunningModels { return .degrees(4) }
        return .degrees(34)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.21, green: 0.17, blue: 0.14), Color(red: 0.11, green: 0.09, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: size * 0.05)
                .padding(size * 0.08)

            Circle()
                .fill(Color(red: 0.73, green: 0.62, blue: 0.45))
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(x: -size * 0.08, y: size * 0.1)

            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.84, green: 0.79, blue: 0.72), Color(red: 0.52, green: 0.48, blue: 0.44)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.11, height: size * 0.58)
                .offset(x: -size * 0.03, y: -size * 0.02)
                .rotationEffect(leverRotation, anchor: .bottom)
                .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.04)

            Circle()
                .fill(accent)
                .frame(width: size * 0.18, height: size * 0.18)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: size * 0.03))
                .offset(x: -size * 0.17, y: size * 0.28)
        }
        .frame(width: size, height: size)
    }
}
