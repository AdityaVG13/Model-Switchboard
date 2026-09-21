import SwiftUI

extension MenuBarContentView {
    var settingsInspector: some View {
        SettingsView(
            hub: hub,
            controllerBaseURL: $controllerBaseURL,
            controllerAuthToken: $controllerAuthToken,
            profilesDirectory: store.profilesDirectory,
            doctorReport: store.doctorReport,
            profileDiagnostics: store.diagnosticsNeedingAttention,
            isRunningControllerDoctor: store.isRunningControllerDoctor,
            launchAtLoginManager: launchAtLoginManager,
            theme: theme,
            accent: accent,
            appVersion: Self.appVersion,
            openProfilesDirectory: store.openProfilesDirectory,
            setProfilesDirectory: { path in
                await store.setProfilesDirectory(path)
            },
            openControllerRoot: store.openControllerRoot,
            runControllerDoctor: {
                Task { await store.refreshDoctorReport() }
            },
            reconnect: reconnect
        )
    }
}
