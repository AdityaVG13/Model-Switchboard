import SwiftUI
import ModelSwitchboardCore

extension HelpView {
    var quickStartBullets: [String] {
        [
            "Model Switchboard already embeds the local controller. The first launch registers it; if macOS asks, allow it in System Settings → General → Login Items & Extensions.",
            "The board starts empty. Open Settings → Open Profiles Folder, copy a file from `examples/` into that folder, fill in your model path (not a placeholder), then Refresh.",
            "Use `Start` to spawn a model, `Activate` to switch your primary endpoint (stopping others), and hold `Stop All` / `Stop Everything` to shut down running models before closing the lid or leaving the machine on battery."
        ]
    }

    var remoteGatewayBullets: [String] {
        [
            "Add a remote host in Settings → Remote Gateways (SSH tunnel or direct agent URL). Remote Hosts in the footer shows live GPU / VRAM / CPU / RAM per box.",
            "SSH mode forwards model ports to this Mac so Copy Endpoint URL works locally. Direct mode talks to the agent over Tailscale or your LAN - MagicDNS `.ts.net` names are preferred over raw 100.x addresses."
        ]
    }

    var profileSetupBullets: [String] {
        [
            "Each profile should define a stable profile name, runtime, host, port, request model ID, and the command needed to launch the server.",
            "For `llama.cpp`, set `MODEL_PATH` or `MODEL_FILE` with `MODEL_ROOT`, plus `SERVER_BIN` if `llama-server` is not already on `PATH`. For MLX, set `MODEL_DIR` or `MODEL_REPO`. For other launchers, keep a named `RUNTIME` and use `START_COMMAND`, `SERVER_BIN`, or `LAUNCH_MODE=external` with a health check.",
            "Keep one centralized profile folder and treat it as the source of truth. ModelSwitchboard reads whatever the controller reports, so the app stays model-agnostic.",
            "If you add new profiles, refresh the app after the controller picks them up."
        ]
    }

    var operatingDisciplineBullets: [String] {
        [
            "Run only the models you actually need. Unified memory pressure on Apple silicon compounds fast once multiple 30B-class profiles and large KV caches are live.",
            "The menu bar stays lightweight by default. It refreshes immediately after your actions, polls every 10 seconds only while a model is live, and falls back to a 10-minute idle cadence when nothing is running.",
            "If a model is starting but not healthy yet, the badge stays amber while the endpoint comes up. That is expected.",
            "If the controller is temporarily unavailable, the app can fall back to cached status instead of showing an empty board."
        ]
    }

    var troubleshootingBullets: [String] {
        [
            "If the board shows a connection error on first launch, enable Model Switchboard in System Settings → General → Login Items & Extensions, then Quit and reopen.",
            "If the board shows stale data, hit `Refresh` or Settings → Reconnect after confirming the controller service is listening on the expected port.",
            "If buttons do nothing, inspect the controller log first. The menu bar app only reflects controller success or failure.",
            "If a profile keeps flapping between running and not running, the launch command is unstable. Fix the launcher instead of repeatedly forcing restart from the UI."
        ]
    }
}
