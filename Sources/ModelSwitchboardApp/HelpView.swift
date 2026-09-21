import SwiftUI
import ModelSwitchboardCore

struct HelpView: View {
    let exampleProfilesDirectory: String?
    let openExampleProfilesDirectory: () -> Void
    let theme: DashboardTheme
    let accent: Color
    let features = AppFeatures.current
    let scrollContentTrailingPadding: CGFloat = 22

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            helpSections
            .padding(.trailing, scrollContentTrailingPadding)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
