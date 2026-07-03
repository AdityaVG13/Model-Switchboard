import SwiftUI

// MARK: - User appearance preferences

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

enum DashboardSidePreference: String, CaseIterable {
    case left
    case right

    var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }

    var inspectorSide: InspectorPanelSide {
        switch self {
        case .left: .leading
        case .right: .trailing
        }
    }
}

enum DashboardAppearanceKeys {
    static let theme = "dashboardTheme"
    static let accent = "dashboardAccent"
    static let sidePanel = "dashboardSidePanel"
    static let menuBarShowsReadyCount = "menuBarShowsReadyCount"
}

// MARK: - Theme tokens (from the Switchboard Panel design)

struct DashboardTheme {
    let panelBg: Color
    let cellBg: Color
    let hoverBg: Color
    let line: Color
    let sub: Color
    let faint: Color
    let btnBg: Color
    let btnFg: Color
    let btnStrongBg: Color
    let btnStrongFg: Color
    let tabOnBg: Color
    let tabOnFg: Color
    let tabOffFg: Color
    let dotOff: Color
    let sparkStroke: Color
    let panelBorder: Color

    static let dark = DashboardTheme(
        panelBg: Color(.sRGB, red: 26 / 255, green: 26 / 255, blue: 29 / 255, opacity: 0.98),
        cellBg: Color.white.opacity(0.05),
        hoverBg: Color.white.opacity(0.06),
        line: Color.white.opacity(0.07),
        sub: Color(.sRGB, red: 142 / 255, green: 142 / 255, blue: 150 / 255),
        faint: Color(.sRGB, red: 110 / 255, green: 110 / 255, blue: 118 / 255),
        btnBg: Color.white.opacity(0.07),
        btnFg: Color(.sRGB, red: 216 / 255, green: 216 / 255, blue: 220 / 255),
        btnStrongBg: Color.white.opacity(0.1),
        btnStrongFg: .white,
        tabOnBg: Color.white.opacity(0.14),
        tabOnFg: .white,
        tabOffFg: Color(.sRGB, red: 154 / 255, green: 154 / 255, blue: 162 / 255),
        dotOff: Color(.sRGB, red: 110 / 255, green: 110 / 255, blue: 118 / 255),
        sparkStroke: Color(.sRGB, red: 154 / 255, green: 154 / 255, blue: 162 / 255),
        panelBorder: Color.white.opacity(0.09)
    )

    static let light = DashboardTheme(
        panelBg: Color(.sRGB, red: 246 / 255, green: 246 / 255, blue: 248 / 255, opacity: 0.99),
        cellBg: Color.black.opacity(0.05),
        hoverBg: Color.black.opacity(0.05),
        line: Color.black.opacity(0.08),
        sub: Color(.sRGB, red: 134 / 255, green: 134 / 255, blue: 139 / 255),
        faint: Color(.sRGB, red: 160 / 255, green: 160 / 255, blue: 166 / 255),
        btnBg: Color.black.opacity(0.06),
        btnFg: Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255),
        btnStrongBg: Color.black.opacity(0.1),
        btnStrongFg: Color(.sRGB, red: 29 / 255, green: 29 / 255, blue: 31 / 255),
        tabOnBg: Color.white.opacity(0.95),
        tabOnFg: Color(.sRGB, red: 29 / 255, green: 29 / 255, blue: 31 / 255),
        tabOffFg: Color(.sRGB, red: 134 / 255, green: 134 / 255, blue: 139 / 255),
        dotOff: Color(.sRGB, red: 180 / 255, green: 180 / 255, blue: 186 / 255),
        sparkStroke: Color(.sRGB, red: 160 / 255, green: 160 / 255, blue: 166 / 255),
        panelBorder: Color.black.opacity(0.1)
    )

    static func resolve(_ scheme: ColorScheme) -> DashboardTheme {
        scheme == .light ? .light : .dark
    }

    static let runningGreen = Color(.sRGB, red: 50 / 255, green: 215 / 255, blue: 75 / 255)
    static let stopRed = Color(.sRGB, red: 1.0, green: 105 / 255, blue: 97 / 255)
    static let pendingOrange = Color.orange
}

// MARK: - Sparkline

struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }

        let maxValue = max(values.max() ?? 100, 1)
        let stepX = rect.width / CGFloat(values.count - 1)
        // Leave headroom so the line never hugs the cell edges.
        let usableHeight = rect.height * 0.86
        let topInset = rect.height * 0.07

        func point(at index: Int) -> CGPoint {
            let normalized = CGFloat(values[index] / maxValue)
            return CGPoint(
                x: rect.minX + CGFloat(index) * stepX,
                y: rect.minY + topInset + usableHeight * (1 - normalized)
            )
        }

        path.move(to: point(at: 0))
        for index in 1..<values.count {
            path.addLine(to: point(at: index))
        }
        return path
    }
}

// MARK: - Segmented tabs (design-styled)

struct DashboardSegmentedTabs<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option
    let theme: DashboardTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Text(label(option))
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        isOn ? theme.tabOnBg : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .foregroundStyle(isOn ? theme.tabOnFg : theme.tabOffFg)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Section label

struct DashboardSectionLabel: View {
    let text: String
    let theme: DashboardTheme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.faint)
    }
}
