import SwiftUI

struct SettingsView: View {
    @Binding var controllerBaseURL: String
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let reconnect: () -> Void
    private let defaultControllerBaseURL = "http://127.0.0.1:8877"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tune the connection without leaving the menu bar. This stays attached to ModelSwitchboard instead of opening a detached desktop window.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Controller Base URL")
                    .font(.caption.bold())
                TextField(defaultControllerBaseURL, text: $controllerBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .textSelection(.enabled)
                Text("Use the loopback controller unless you intentionally moved the control plane to another host or port.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Launch At Login")
                    .font(.caption.bold())

                if launchAtLoginManager.isAvailable {
                    Toggle(
                        "Open Model Switchboard when you log in",
                        isOn: Binding(
                            get: {
                                launchAtLoginManager.isEnabled || launchAtLoginManager.requiresApproval
                            },
                            set: { launchAtLoginManager.setEnabled($0) }
                        )
                    )

                    Text("The app is idle when closed in the menu bar. It does not keep the heavy model refresh loop running unless the menu is open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if launchAtLoginManager.requiresApproval {
                        Text("macOS needs you to approve the login item in System Settings > General > Login Items.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Launch at login requires a newer macOS Service Management API.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = launchAtLoginManager.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Use Default") {
                    controllerBaseURL = defaultControllerBaseURL
                }
                Button("Reconnect") {
                    reconnect()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            launchAtLoginManager.refresh()
        }
    }
}
