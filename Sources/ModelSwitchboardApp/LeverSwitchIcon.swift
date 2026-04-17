import SwiftUI

struct LeverSwitchIcon: View {
    let hasReadyModels: Bool
    let hasRunningModels: Bool
    var size: CGFloat = 18

    private var lineColor: Color {
        .primary.opacity(0.96)
    }

    private var accent: Color {
        if hasReadyModels { return Color(red: 0.26, green: 0.88, blue: 0.51) }
        if hasRunningModels { return Color(red: 0.96, green: 0.68, blue: 0.18) }
        return Color(red: 0.96, green: 0.29, blue: 0.27)
    }

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let stroke = max(1.6, s * 0.12)
            let chipSize = s * 0.42
            let chipOrigin = CGPoint(x: (s - chipSize) / 2, y: (s - chipSize) / 2)
            let leftPins = [0.34, 0.5, 0.66].map { s * $0 }
            let rightPins = [0.34, 0.5, 0.66].map { s * $0 }

            ZStack {
                Path { path in
                    for y in leftPins {
                        path.move(to: CGPoint(x: s * 0.08, y: y))
                        path.addLine(to: CGPoint(x: chipOrigin.x, y: y))
                    }

                    for y in rightPins {
                        path.move(to: CGPoint(x: chipOrigin.x + chipSize, y: y))
                        path.addLine(to: CGPoint(x: s * 0.92, y: y))
                    }

                    path.move(to: CGPoint(x: s * 0.50, y: s * 0.08))
                    path.addLine(to: CGPoint(x: s * 0.50, y: chipOrigin.y))

                    path.move(to: CGPoint(x: chipOrigin.x + chipSize * 0.22, y: chipOrigin.y + chipSize * 0.30))
                    path.addLine(to: CGPoint(x: chipOrigin.x + chipSize * 0.50, y: chipOrigin.y + chipSize * 0.30))
                    path.addLine(to: CGPoint(x: chipOrigin.x + chipSize * 0.50, y: chipOrigin.y + chipSize * 0.56))
                    path.addLine(to: CGPoint(x: chipOrigin.x + chipSize * 0.72, y: chipOrigin.y + chipSize * 0.56))

                    path.move(to: CGPoint(x: chipOrigin.x + chipSize * 0.34, y: chipOrigin.y + chipSize * 0.72))
                    path.addLine(to: CGPoint(x: chipOrigin.x + chipSize * 0.50, y: chipOrigin.y + chipSize * 0.56))
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))

                RoundedRectangle(cornerRadius: s * 0.10, style: .continuous)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                    .frame(width: chipSize, height: chipSize)

                Circle()
                    .fill(lineColor)
                    .frame(width: s * 0.12, height: s * 0.12)
                    .offset(x: chipOrigin.x + chipSize * 0.28 - s * 0.50, y: chipOrigin.y + chipSize * 0.30 - s * 0.50)

                Circle()
                    .fill(lineColor)
                    .frame(width: s * 0.12, height: s * 0.12)
                    .offset(x: chipOrigin.x + chipSize * 0.72 - s * 0.50, y: chipOrigin.y + chipSize * 0.56 - s * 0.50)

                Circle()
                    .fill(accent)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.32), lineWidth: max(1, s * 0.03))
                    )
                    .frame(width: s * 0.22, height: s * 0.22)
                    .offset(x: chipOrigin.x + chipSize * 0.18 - s * 0.50, y: chipOrigin.y + chipSize * 0.72 - s * 0.50)
            }
            .frame(width: s, height: s)
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .linear)
    }
}
