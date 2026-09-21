import SwiftUI

extension HoldToConfirmTextButton {
    var fillsWidth: Bool {
        if case .filled = chrome { return true }
        return false
    }

    var labelColor: Color {
        switch chrome {
        case .plain:
            return color
        case .filled(_, let foreground):
            return foreground
        }
    }

    @ViewBuilder
    var progressBackground: some View {
        switch chrome {
        case .plain:
            GeometryReader { geo in
                color.opacity(0.22)
                    .frame(width: max(0, geo.size.width * progress))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        case .filled(let background, _):
            ZStack(alignment: .leading) {
                background
                GeometryReader { geo in
                    color.opacity(0.35)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
        }
    }
}
