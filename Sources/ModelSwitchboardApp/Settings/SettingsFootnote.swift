import SwiftUI

struct SettingsFootnote: View {
    let text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
