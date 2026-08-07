import SwiftUI
import ModelSwitchboardCore

struct HelpView: View {
    let exampleProfilesDirectory: String?
    let openExampleProfilesDirectory: () -> Void
    let theme: DashboardTheme
    let accent: Color
    private let features = AppFeatures.current
    private let scrollContentTrailingPadding: CGFloat = 22

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                section(
                    title: "Quick Start",
                    bullets: [
                        "Install the local controller service first. \(features.appDisplayName) assumes a controller is serving status and actions at `\(ControllerEndpointDefaults.baseURLString)` by default.",
                        "Put model launch profiles in the controller's `model-profiles` directory. Settings shows the live path reported by the controller and can open that folder in Finder.",
                        "Use `Start` to spawn a model, `Activate` to switch your primary endpoint (stopping others), and hold `Stop All` / `Stop Everything` to shut down running models before closing the lid or leaving the machine on battery."
                    ]
                )

                section(
                    title: "Remote Gateways",
                    bullets: [
                        "Add a remote host in Settings → Remote Gateways (SSH tunnel or direct agent URL). Remote Hosts in the footer shows live GPU / VRAM / CPU / RAM per box.",
                        "SSH mode forwards model ports to this Mac so Copy Endpoint URL works locally. Direct mode talks to the agent over Tailscale or your LAN — MagicDNS `.ts.net` names are preferred over raw 100.x addresses."
                    ]
                )

                section(
                    title: "Profile Setup",
                    bullets: [
                        "Each profile should define a stable profile name, runtime, host, port, request model ID, and the command needed to launch the server.",
                        "For `llama.cpp`, set `MODEL_PATH` or `MODEL_FILE` with `MODEL_ROOT`, plus `SERVER_BIN` if `llama-server` is not already on `PATH`. For MLX, set `MODEL_DIR` or `MODEL_REPO`. For other launchers, keep a named `RUNTIME` and use `START_COMMAND`, `SERVER_BIN`, or `LAUNCH_MODE=external` with a health check.",
                        "Keep one centralized profile folder and treat it as the source of truth. ModelSwitchboard reads whatever the controller reports, so the app stays model-agnostic.",
                        "If you add new profiles, refresh the app after the controller picks them up."
                    ]
                )

                section(
                    title: "Good Operating Discipline",
                    bullets: [
                        "Run only the models you actually need. Unified memory pressure on Apple silicon compounds fast once multiple 30B-class profiles and large KV caches are live.",
                        "The menu bar stays lightweight by default. It refreshes immediately after your actions, polls every 10 seconds only while a model is live, and falls back to a 10-minute idle cadence when nothing is running.",
                        "If a model is starting but not healthy yet, the badge stays amber while the endpoint comes up. That is expected.",
                        "If the controller is temporarily unavailable, the app can fall back to cached status instead of showing an empty board."
                    ]
                )

                section(
                    title: "Troubleshooting",
                    bullets: [
                        "If the board shows stale data, hit `Refresh` or `Reconnect` after confirming the controller service is listening on the expected port.",
                        "If buttons do nothing, inspect the controller log first. The menu bar app only reflects controller success or failure.",
                        "If a profile keeps flapping between running and not running, the launch command is unstable. Fix the launcher instead of repeatedly forcing restart from the UI."
                    ]
                )

                exampleProfilesSection

                section(
                    title: "Power User Extras",
                    bullets: powerUserBullets
                )
            }
            .padding(.trailing, scrollContentTrailingPadding)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(theme.faint)
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(theme.faint)
                    Text(bullet)
                        .font(.footnote)
                        .foregroundStyle(theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var exampleProfilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Example Profiles")
                .font(.caption.bold())
                .foregroundStyle(theme.faint)

            Text("Use the bundled example manifests as clean starting points for `llama.cpp`, MLX, `rvllm-mlx`, and generic OpenAI-compatible profiles. Copy one, rename it, then fill in your own model path, server binary, and runtime-specific flags.")
                .font(.footnote)
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)

            if let exampleProfilesDirectory, !exampleProfilesDirectory.isEmpty {
                Text(exampleProfilesDirectory)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.sub)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.hoverBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button("Open Example Profiles", action: openExampleProfilesDirectory)
                    .buttonStyle(QuietCraftPressStyle())
                    .foregroundStyle(accent)
            } else {
                Text("The controller root is not available yet, so the bundled example-profile folder cannot be resolved.")
                    .font(.footnote)
                    .foregroundStyle(DashboardTheme.pendingOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var powerUserBullets: [String] {
        var bullets = [
            "Raycast users can add the repo's `Integrations/Raycast/Script Commands` folder directly in Raycast for keyboard-first actions.",
            "The bundled `Scripts/model-switchboardctl` CLI exposes controller actions like `status`, `activate`, `stop-all`, and `open-profiles` without touching the menu bar.",
        ]
        if features.supportsBenchmarks {
            bullets.append("Benchmark controls live in the Plus edition, and results are viewable directly in the in-app Benchmarks panel.")
        }
        return bullets
    }
}
