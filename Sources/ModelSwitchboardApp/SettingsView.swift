import SwiftUI
import ModelSwitchboardCore

struct SettingsView: View {
    @Binding var controllerBaseURL: String
    @Binding var controllerAuthToken: String
    let profilesDirectory: String?
    let controllerRoot: String?
    let doctorReport: DoctorReport?
    let profileDiagnostics: [ProfileDiagnostic]
    let isRunningControllerDoctor: Bool
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let theme: DashboardTheme
    let accent: Color
    let appVersion: String
    let openProfilesDirectory: () -> Void
    let openControllerRoot: () -> Void
    let runControllerDoctor: () -> Void
    let reconnect: () -> Void

    @AppStorage(DashboardAppearanceKeys.theme)
    private var themePreferenceRaw: String = DashboardThemePreference.system.rawValue

    @AppStorage(DashboardAppearanceKeys.accent)
    private var accentRaw: String = DashboardAccent.orange.rawValue

    @AppStorage(DashboardAppearanceKeys.sidePanel)
    private var sidePreferenceRaw: String = DashboardSidePreference.right.rawValue

    @AppStorage(DashboardAppearanceKeys.menuBarShowsReadyCount)
    private var menuBarShowsReadyCount = true

    private let defaultControllerBaseURL = "http://127.0.0.1:8877"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    appearanceGroup
                    connectionGroup
                    behaviorGroup
                    controllerGroup
                }
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10))
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
        }
    }

    // MARK: - Appearance

    private var appearanceGroup: some View {
        settingsGroup("APPEARANCE") {
            settingsRow("Theme") {
                segmented(
                    options: DashboardThemePreference.allCases.map(\.rawValue),
                    labels: DashboardThemePreference.allCases.map(\.label),
                    selection: $themePreferenceRaw
                )
            }
            groupDivider
            settingsRow("Accent color") {
                HStack(spacing: 6) {
                    ForEach(DashboardAccent.allCases, id: \.rawValue) { choice in
                        Circle()
                            .fill(choice.color)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .stroke(choice.rawValue == accentRaw ? Color.primary : .clear, lineWidth: 2)
                            }
                            .contentShape(Circle())
                            .onTapGesture { accentRaw = choice.rawValue }
                            .accessibilityLabel("\(choice.rawValue) accent")
                            .accessibilityAddTraits(choice.rawValue == accentRaw ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            groupDivider
            settingsRow("Side panel opens") {
                segmented(
                    options: DashboardSidePreference.allCases.map(\.rawValue),
                    labels: DashboardSidePreference.allCases.map(\.label),
                    selection: $sidePreferenceRaw
                )
            }
            groupDivider
            settingsRow("Menu bar shows") {
                segmented(
                    options: ["icon", "count"],
                    labels: ["Icon", "Ready count"],
                    selection: Binding(
                        get: { menuBarShowsReadyCount ? "count" : "icon" },
                        set: { menuBarShowsReadyCount = $0 == "count" }
                    )
                )
            }
        }
    }

    // MARK: - Connection

    private var connectionGroup: some View {
        settingsGroup("CONNECTION") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Controller base URL")
                    .font(.system(size: 12.5))
                TextField(defaultControllerBaseURL, text: $controllerBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                Text("Bearer token (optional)")
                    .font(.system(size: 12.5))
                SecureField("Required for --unsafe-bind controllers", text: $controllerAuthToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                HStack(spacing: 10) {
                    settingsLinkButton("Use Default") {
                        controllerBaseURL = defaultControllerBaseURL
                    }
                    settingsLinkButton("Reconnect", emphasized: true, action: reconnect)
                }
                Text("Use the loopback controller unless you intentionally moved the control plane to another host or port. When the controller requires auth, paste the bearer token here (never in the URL). Model paths and launch commands stay in controller profile files.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        }
    }

    // MARK: - Behavior

    private var behaviorGroup: some View {
        settingsGroup("BEHAVIOR") {
            VStack(alignment: .leading, spacing: 6) {
                toggleRow(
                    "Launch at login",
                    subtitle: "Start Model Switchboard with macOS",
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled || launchAtLoginManager.requiresApproval },
                        set: { launchAtLoginManager.setEnabled($0) }
                    ),
                    disabled: !launchAtLoginManager.isAvailable
                )

                if !launchAtLoginManager.isAvailable {
                    settingsFootnote("Launch at login requires a newer macOS Service Management API.", color: theme.sub)
                }
                if launchAtLoginManager.requiresApproval {
                    settingsFootnote("macOS needs you to approve the login item in System Settings > General > Login Items.", color: DashboardTheme.pendingOrange)
                }
                if let error = launchAtLoginManager.lastError {
                    settingsFootnote(error, color: DashboardTheme.stopRed)
                }
                settingsFootnote("The app is idle when closed in the menu bar. Open, it refreshes every 10 minutes while idle and every 30 seconds while a model is live.", color: theme.sub)
            }
            .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        }
    }

    // MARK: - Controller

    private var controllerGroup: some View {
        settingsGroup("CONTROLLER") {
            VStack(alignment: .leading, spacing: 8) {
                if let profilesDirectory, !profilesDirectory.isEmpty {
                    Text(profilesDirectory)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(theme.sub)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack(spacing: 10) {
                        settingsLinkButton("Open Profiles Folder", action: openProfilesDirectory)
                        if let controllerRoot, !controllerRoot.isEmpty {
                            settingsLinkButton("Open Controller Root", action: openControllerRoot)
                        }
                    }
                } else {
                    settingsFootnote("No profile folder reported yet. Start the controller and reconnect to load its configured model-profiles path.", color: DashboardTheme.pendingOrange)
                }

                groupDivider

                if let doctorReport {
                    doctorSummary(doctorReport)
                }

                settingsLinkButton(
                    isRunningControllerDoctor ? "Running Controller Doctor\u{2026}" : "Run Controller Doctor",
                    emphasized: true,
                    disabled: isRunningControllerDoctor,
                    action: runControllerDoctor
                )

                if profileDiagnostics.isEmpty {
                    settingsFootnote("No profile errors or warnings on the latest controller refresh.", color: DashboardTheme.runningGreen)
                } else {
                    ForEach(profileDiagnostics) { diagnostic in
                        diagnosticCard(diagnostic)
                    }
                }
            }
            .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        }
    }

    private func doctorSummary(_ report: DoctorReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                report.controller.reachable ? "Controller reachable" : "Controller unreachable",
                systemImage: report.controller.reachable ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(report.controller.reachable ? DashboardTheme.runningGreen : DashboardTheme.stopRed)

            Label(
                report.launchAgent.running ? "Launch agent running" : "Launch agent not running",
                systemImage: report.launchAgent.running ? "bolt.circle.fill" : "bolt.slash.circle.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(report.launchAgent.running ? DashboardTheme.runningGreen : DashboardTheme.pendingOrange)

            Text(report.controller.url)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(theme.sub)
                .textSelection(.enabled)
        }
    }

    private func diagnosticCard(_ diagnostic: ProfileDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diagnostic.displayName)
                .font(.system(size: 11.5, weight: .semibold))
            ForEach(diagnostic.errors, id: \.self) { error in
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.stopRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(diagnostic.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.pendingOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(diagnostic.baseURL)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.sub)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.hoverBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Building blocks

    private func settingsGroup(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardSectionLabel(text: label, theme: theme)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func settingsRow(_ label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
            Spacer()
            trailing()
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
    }

    private var groupDivider: some View {
        theme.line
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private func segmented(options: [String], labels: [String], selection: Binding<String>) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(zip(options, labels)), id: \.0) { option, label in
                let isOn = selection.wrappedValue == option
                Text(label)
                    .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(
                        isOn ? theme.tabOnBg : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .foregroundStyle(isOn ? theme.tabOnFg : theme.tabOffFg)
                    .contentShape(Rectangle())
                    .onTapGesture { selection.wrappedValue = option }
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func toggleRow(_ label: String, subtitle: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12.5))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(accent)
                .disabled(disabled)
                .accessibilityLabel(label)
        }
    }

    private func settingsLinkButton(
        _ title: String,
        emphasized: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .semibold : .regular))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? theme.faint : (emphasized ? accent : theme.btnFg))
        .disabled(disabled)
    }

    private func settingsFootnote(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
