import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(
                    title: "Quick Start",
                    bullets: [
                        "Install the local controller service first. ModelSwitchboard assumes a controller is serving status and actions at `http://127.0.0.1:8877` by default.",
                        "Put model launch profiles in the controller's `model-profiles` directory. Profiles can point to `llama.cpp`, MLX, or any custom command adapter that exposes an OpenAI-compatible endpoint.",
                        "Use `Start` to spawn a model, `Activate` to switch your primary endpoint, and `Stop All` before closing the lid or leaving the machine on battery."
                    ]
                )

                section(
                    title: "Profile Setup",
                    bullets: [
                        "Each profile should define a stable profile name, runtime, host, port, request model ID, and the command needed to launch the server.",
                        "Keep one centralized profile folder and treat it as the source of truth. ModelSwitchboard reads whatever the controller reports, so the app stays model-agnostic.",
                        "If you add new profiles, refresh the app after the controller picks them up."
                    ]
                )

                section(
                    title: "Good Operating Discipline",
                    bullets: [
                        "Run only the models you actually need. Unified memory pressure on Apple silicon compounds fast once multiple 30B-class profiles and large KV caches are live.",
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
}
