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

enum DashboardAppearanceKeys {
    static let theme = "dashboardTheme"
    static let accent = "dashboardAccent"
    static let menuBarShowsReadyCount = "menuBarShowsReadyCount"
}

// MARK: - Theme tokens (from the Switchboard Panel design)

struct DashboardTheme {
    /// Opaque panel fill — keep solid so Auto/Light/Dark swaps never desync.
    let panelBg: Color
    let cellBg: Color
    let hoverBg: Color
    let line: Color
    /// Primary titles / model names (never use Color.primary in MenuBarExtra).
    let label: Color
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
    /// Text field / secure field fill (settings).
    let fieldBg: Color
    let fieldFg: Color

    static let dark = DashboardTheme(
        panelBg: Color(.sRGB, red: 26 / 255, green: 26 / 255, blue: 29 / 255),
        cellBg: Color(.sRGB, red: 40 / 255, green: 40 / 255, blue: 44 / 255),
        hoverBg: Color(.sRGB, red: 48 / 255, green: 48 / 255, blue: 52 / 255),
        line: Color(.sRGB, red: 55 / 255, green: 55 / 255, blue: 60 / 255),
        label: Color(.sRGB, red: 245 / 255, green: 245 / 255, blue: 247 / 255),
        sub: Color(.sRGB, red: 162 / 255, green: 162 / 255, blue: 170 / 255),
        faint: Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255),
        btnBg: Color(.sRGB, red: 48 / 255, green: 48 / 255, blue: 52 / 255),
        btnFg: Color(.sRGB, red: 220 / 255, green: 220 / 255, blue: 224 / 255),
        btnStrongBg: Color(.sRGB, red: 58 / 255, green: 58 / 255, blue: 64 / 255),
        btnStrongFg: Color.white,
        tabOnBg: Color(.sRGB, red: 58 / 255, green: 58 / 255, blue: 64 / 255),
        tabOnFg: Color.white,
        tabOffFg: Color(.sRGB, red: 154 / 255, green: 154 / 255, blue: 162 / 255),
        dotOff: Color(.sRGB, red: 110 / 255, green: 110 / 255, blue: 118 / 255),
        sparkStroke: Color(.sRGB, red: 154 / 255, green: 154 / 255, blue: 162 / 255),
        panelBorder: Color(.sRGB, red: 55 / 255, green: 55 / 255, blue: 60 / 255),
        fieldBg: Color(.sRGB, red: 36 / 255, green: 36 / 255, blue: 40 / 255),
        fieldFg: Color(.sRGB, red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    )

    /// Light mode tuned for WCAG-ish contrast on model rows (image #2 failure).
    static let light = DashboardTheme(
        panelBg: Color(.sRGB, red: 244 / 255, green: 244 / 255, blue: 247 / 255),
        cellBg: Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 255 / 255),
        hoverBg: Color(.sRGB, red: 232 / 255, green: 232 / 255, blue: 237 / 255),
        line: Color(.sRGB, red: 210 / 255, green: 210 / 255, blue: 216 / 255),
        label: Color(.sRGB, red: 28 / 255, green: 28 / 255, blue: 30 / 255),
        sub: Color(.sRGB, red: 72 / 255, green: 72 / 255, blue: 78 / 255),
        faint: Color(.sRGB, red: 100 / 255, green: 100 / 255, blue: 108 / 255),
        btnBg: Color(.sRGB, red: 228 / 255, green: 228 / 255, blue: 234 / 255),
        btnFg: Color(.sRGB, red: 40 / 255, green: 40 / 255, blue: 46 / 255),
        btnStrongBg: Color(.sRGB, red: 214 / 255, green: 214 / 255, blue: 220 / 255),
        btnStrongFg: Color(.sRGB, red: 22 / 255, green: 22 / 255, blue: 24 / 255),
        tabOnBg: Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 255 / 255),
        tabOnFg: Color(.sRGB, red: 22 / 255, green: 22 / 255, blue: 24 / 255),
        tabOffFg: Color(.sRGB, red: 90 / 255, green: 90 / 255, blue: 98 / 255),
        dotOff: Color(.sRGB, red: 150 / 255, green: 150 / 255, blue: 158 / 255),
        sparkStroke: Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255),
        panelBorder: Color(.sRGB, red: 200 / 255, green: 200 / 255, blue: 208 / 255),
        fieldBg: Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 255 / 255),
        fieldFg: Color(.sRGB, red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    )

    static func resolve(_ scheme: ColorScheme) -> DashboardTheme {
        scheme == .light ? .light : .dark
    }

    static let runningGreen = Color(.sRGB, red: 50 / 255, green: 215 / 255, blue: 75 / 255)
    static let stopRed = Color(.sRGB, red: 1.0, green: 105 / 255, blue: 97 / 255)
    static let pendingOrange = Color(.sRGB, red: 1.0, green: 0.58, blue: 0.0)
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

    @Namespace private var tabChipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    guard option != selection else { return }
                    if reduceMotion {
                        selection = option
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selection = option
                        }
                    }
                } label: {
                    Text(label(option))
                        .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .frame(minHeight: 24)
                        .foregroundStyle(isOn ? theme.tabOnFg : theme.tabOffFg)
                        .contentShape(Rectangle())
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(theme.tabOnBg)
                                    .matchedGeometryEffect(id: "selected-tab", in: tabChipNamespace)
                            }
                        }
                }
                .buttonStyle(QuietCraftPressStyle())
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder.opacity(0.8), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter")
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
