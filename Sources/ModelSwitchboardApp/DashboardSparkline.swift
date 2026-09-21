import SwiftUI

struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        path.move(to: point(at: 0, in: rect))
        for index in 1..<values.count {
            path.addLine(to: point(at: index, in: rect))
        }
        return path
    }

    func point(at index: Int, in rect: CGRect) -> CGPoint {
        let maxValue = max(values.max() ?? 100, 1)
        let stepX = rect.width / CGFloat(values.count - 1)
        // Leave headroom so the line never hugs the cell edges.
        let usableHeight = rect.height * 0.86
        let topInset = rect.height * 0.07
        let normalized = CGFloat(values[index] / maxValue)
        return CGPoint(
            x: rect.minX + CGFloat(index) * stepX,
            y: rect.minY + topInset + usableHeight * (1 - normalized)
        )
    }
}
