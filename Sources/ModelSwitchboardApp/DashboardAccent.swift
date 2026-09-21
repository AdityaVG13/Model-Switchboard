import SwiftUI

enum DashboardAccent: String, CaseIterable {
    case orange
    case blue
    case green
    case purple

    var color: Color {
        switch self {
        case .orange: Color(.sRGB, red: 1.0, green: 0.62, blue: 0.04)   // #ff9f0a
        case .blue: Color(.sRGB, red: 0.04, green: 0.52, blue: 1.0)     // #0a84ff
        case .green: Color(.sRGB, red: 0.20, green: 0.84, blue: 0.29)   // #32d74b
        case .purple: Color(.sRGB, red: 0.75, green: 0.35, blue: 0.95)  // #bf5af2
        }
    }
}
