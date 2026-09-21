import SwiftUI
import ModelSwitchboardCore

extension SettingsView {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                settingsSections
            }
            .frame(maxHeight: .infinity)

            theme.line.frame(height: 1)
            HStack {
                Text("Model Switchboard v\(appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.faint)
                Spacer()
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        }
        .onAppear {
            launchAtLoginManager.refresh()
            profilesDirectoryDraft = profilesDirectory ?? ""
        }
        .onChange(of: profilesDirectory) { _, newValue in
            profilesDirectoryDraft = newValue ?? ""
        }
    }
}
