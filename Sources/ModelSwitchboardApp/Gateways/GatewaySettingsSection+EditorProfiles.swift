import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @ViewBuilder
    func existingGatewayProfiles(_ runtime: GatewayRuntime) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            field(
                "Profiles folder (on host)",
                text: $profilesDirectoryDraft,
                prompt: "~/model-profiles",
                monospaced: true
            )
            Text("Path on the remote host where model profile .env/.json files live. Saving updates the running agent without reinstall.")
                .font(.system(size: 10))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            linkButton("Save Profiles Folder", emphasized: true) {
                Task { await runtime.store.setProfilesDirectory(profilesDirectoryDraft) }
            }
        }
        .onAppear {
            profilesDirectoryDraft = runtime.store.profilesDirectory ?? ""
        }
        .onChange(of: runtime.store.profilesDirectory) { _, newValue in
            profilesDirectoryDraft = newValue ?? ""
        }
    }
}
