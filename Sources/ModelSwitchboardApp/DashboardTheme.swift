import SwiftUI

// MARK: - Theme tokens (from the Switchboard Panel design)

struct DashboardTheme {
    /// Opaque panel fill - keep solid so Auto/Light/Dark swaps never desync.
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
}
