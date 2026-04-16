import SwiftUI

struct SettingsView: View {
    @Binding var controllerBaseURL: String
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
    }
}
