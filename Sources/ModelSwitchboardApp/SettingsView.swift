import SwiftUI
import ModelSwitchboardCore

struct SettingsView: View {
    @Binding var controllerBaseURL: String
    let profilesDirectory: String?
    let controllerRoot: String?
    let doctorReport: DoctorReport?
    let profileDiagnostics: [ProfileDiagnostic]
    let isRunningControllerDoctor: Bool
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let openProfilesDirectory: () -> Void
    let openControllerRoot: () -> Void
    let runControllerDoctor: () -> Void
    let reconnect: () -> Void
    private let defaultControllerBaseURL = "http://127.0.0.1:8877"
    private let scrollContentTrailingPadding: CGFloat = 22

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("These preferences only control app connectivity. Model paths and launch commands stay in controller profile files.")
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

                    Text("Model Switchboard does not store model locations. It reads profile metadata from the running controller so the app stays user-agnostic.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let profilesDirectory, !profilesDirectory.isEmpty {
                        pathBlock(title: "Profiles Folder", value: profilesDirectory)

                        VStack(alignment: .leading, spacing: 8) {
                            Button("Open Profiles Folder", action: openProfilesDirectory)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let controllerRoot, !controllerRoot.isEmpty {
                                Button("Open Controller Root", action: openControllerRoot)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Text("No profile folder reported yet. Start the controller and reconnect to load its configured `model-profiles` path.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Controller Doctor")
                        .font(.caption.bold())

                    Text("Run the controller doctor to re-check controller reachability, launch-agent status, and every profile manifest against the live adapter rules.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let doctorReport {
                        doctorSummaryCard(doctorReport)
                    } else {
                        Text("No doctor report loaded yet. Run it once after the controller comes up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: runControllerDoctor) {
                        if isRunningControllerDoctor {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Running Controller Doctor")
                            }
                        } else {
                            Label("Run Controller Doctor", systemImage: "stethoscope")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunningControllerDoctor)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Validation")
                        .font(.caption.bold())

                    Text("These checks come from the controller doctor report. Fix these profile errors before expecting `Activate` or health checks to behave correctly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if profileDiagnostics.isEmpty {
                        Text("No profile errors or warnings on the latest controller refresh.")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(profileDiagnostics) { diagnostic in
                            profileDiagnosticCard(diagnostic)
                        }
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
            .padding(.trailing, scrollContentTrailingPadding)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func profileDiagnosticCard(_ diagnostic: ProfileDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(diagnostic.displayName)
                .font(.footnote.weight(.semibold))

            if !diagnostic.errors.isEmpty {
                ForEach(diagnostic.errors, id: \.self) { error in
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !diagnostic.warnings.isEmpty {
                ForEach(diagnostic.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(diagnostic.baseURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func doctorSummaryCard(_ report: DoctorReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                report.controller.reachable ? "Controller reachable" : "Controller unreachable",
                systemImage: report.controller.reachable ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(report.controller.reachable ? .green : .red)

            Label(
                report.launchAgent.running ? "Launch agent running" : "Launch agent not running",
                systemImage: report.launchAgent.running ? "bolt.circle.fill" : "bolt.slash.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(report.launchAgent.running ? .green : .orange)

            Text(report.controller.url)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
