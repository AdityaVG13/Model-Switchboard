import SwiftUI

struct SettingsView: View {
    @Binding var controllerBaseURL: String
    let profilesDirectory: String?
    let controllerRoot: String?
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let openProfilesDirectory: () -> Void
    let openControllerRoot: () -> Void
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
                Text("Model Profile Source Of Truth")
                    .font(.caption.bold())

                Text("Users set model locations in the controller's profile manifests, not in app preferences. Each `.env` or `.json` file in `model-profiles` defines the runtime, model path, port, and launch behavior for one local model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let profilesDirectory, !profilesDirectory.isEmpty {
                    pathBlock(title: "Profiles Folder", value: profilesDirectory)

                    HStack {
                        Button("Open Profiles Folder", action: openProfilesDirectory)

                        if let controllerRoot, !controllerRoot.isEmpty {
                            Button("Open Controller Root", action: openControllerRoot)
                        }
                    }
                } else {
                    Text("Connect to a running controller once and Model Switchboard will surface the live `model-profiles` path here.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

                    Text("The app is idle when closed in the menu bar. When the menu is open, it refreshes every 10 minutes while idle, every 30 seconds while a model is live, and faster only during active actions or benchmarks.")
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

    private func pathBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
