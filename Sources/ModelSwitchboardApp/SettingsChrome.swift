import SwiftUI

/// Shared Settings chrome. Screens pass labels and bindings; they do not
/// restyle QuietCraft / DashboardTheme per form.
enum SettingsChrome {
    static let rowInsets = EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12)

    static func optionalString(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
