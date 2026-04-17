import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                logoPreviewSection

                section(
                    title: "Quick Start",
                    bullets: [
                        "Install the local controller service first. ModelSwitchboard assumes a controller is serving status and actions at `http://127.0.0.1:8877` by default.",
                        "Put model launch profiles in the controller's `model-profiles` directory. Settings now shows the live path reported by the controller and can open that folder in Finder.",
                        "Use `Start` to spawn a model, `Activate` to switch your primary endpoint, and `Stop All` before closing the lid or leaving the machine on battery."
                    ]
                )

                section(
                    title: "Profile Setup",
                    bullets: [
                        "Each profile should define a stable profile name, runtime, host, port, request model ID, and the command needed to launch the server.",
                        "For `llama.cpp`, set `MODEL_PATH` or `MODEL_FILE`. For MLX, set `MODEL_DIR` or `MODEL_REPO`. For custom launchers, use `START_COMMAND` and a health check.",
                        "Keep one centralized profile folder and treat it as the source of truth. ModelSwitchboard reads whatever the controller reports, so the app stays model-agnostic.",
                        "If you add new profiles, refresh the app after the controller picks them up."
                    ]
                )

                section(
                    title: "Good Operating Discipline",
                    bullets: [
                        "Run only the models you actually need. Unified memory pressure on Apple silicon compounds fast once multiple 30B-class profiles and large KV caches are live.",
                        "The menu bar stays lightweight by default. It refreshes immediately after your actions, polls every 30 seconds only while a model is live, and falls back to a 10-minute idle cadence when nothing is running.",
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

                section(
                    title: "Power User Extras",
                    bullets: [
                        "Raycast users can add the repo's `Integrations/Raycast/Script Commands` folder directly in Raycast for keyboard-first actions.",
                        "The bundled `Scripts/model-switchboardctl` CLI exposes controller actions like `status`, `activate`, `stop-all`, and `open-profiles` without touching the menu bar.",
                        "The browser dashboard is intentionally compact now. Use it when you want a larger surface than the menu bar, not a second product."
                    ]
                )
            }
        }
    }

    private var logoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu Bar Mark")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text("The menu bar mark uses a native template symbol so it stays readable on both dark and light menu bars at true menu-bar size.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                logoStatePreview(title: "Ready", hasReadyModels: true, hasRunningModels: false)
                logoStatePreview(title: "Running", hasReadyModels: false, hasRunningModels: true)
                logoStatePreview(title: "Idle", hasReadyModels: false, hasRunningModels: false)
            }
        }
    }

    private func section(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(bullet)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func logoStatePreview(title: String, hasReadyModels: Bool, hasRunningModels: Bool) -> some View {
        VStack(spacing: 8) {
            LeverSwitchIcon(
                hasReadyModels: hasReadyModels,
                hasRunningModels: hasRunningModels,
                size: 52
            )
            .frame(width: 62, height: 62)
            .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
