import SwiftUI

enum DashboardThemePreference: String, CaseIterable {
    case system
    case dark
    case light

    var label: String {
        switch self {
        case .system: "Auto"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}
