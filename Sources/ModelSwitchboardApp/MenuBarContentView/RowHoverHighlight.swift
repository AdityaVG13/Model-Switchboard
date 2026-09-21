import SwiftUI

/// Hover highlight for list rows (SwiftUI has no `style-hover`; track it manually).
struct RowHoverHighlight: View {
    let color: Color
    @State private var isHovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovering ? color : .clear)
            .onHover { isHovering = $0 }
    }
}
