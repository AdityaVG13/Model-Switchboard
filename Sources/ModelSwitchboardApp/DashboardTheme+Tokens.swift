import SwiftUI

extension DashboardTheme {
    static func srgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
    }

    static func resolve(_ scheme: ColorScheme) -> DashboardTheme {
        scheme == .light ? .light : .dark
    }

    static let runningGreen = srgb(50, 215, 75)
    static let stopRed = srgb(255, 105, 97)
    static let pendingOrange = Color(.sRGB, red: 1.0, green: 0.58, blue: 0.0)
}
