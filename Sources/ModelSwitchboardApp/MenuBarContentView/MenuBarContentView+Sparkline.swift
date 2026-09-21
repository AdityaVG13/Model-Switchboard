import SwiftUI

extension MenuBarContentView {
    func utilizationAccessibilityLabel(label: String, value: Double?) -> String {
        if let value {
            return "\(label) \(Int(value.rounded())) percent"
        }
        return "\(label) unavailable"
    }

    @ViewBuilder
    func utilizationSparkline(_ history: [Double]) -> some View {
        if history.isEmpty {
            Color.clear.frame(height: 14)
        } else {
            Sparkline(values: history)
                .stroke(theme.sparkStroke, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(height: 14)
        }
    }

    func utilizationHelp(label: String, value: Double?, helpText: String?) -> String? {
        if let helpText, !helpText.isEmpty { return helpText }
        if label == "GPU", value == nil {
            return "GPU percentage unavailable on this macOS API path."
        }
        return nil
    }
}
