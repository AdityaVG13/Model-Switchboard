# Model Switchboard

A native macOS menu bar app for switching between local model runtimes.

`Model Switchboard` is intentionally model-agnostic. It does not care whether the backend launches `llama.cpp`, MLX, Ollama, vLLM, or something else. It talks to a controller API that exposes model profiles and lifecycle actions. The app is generic. The controller or runtime adapter can live in any folder or repo, as long as it serves the expected HTTP contract.

## Why this exists

Most local-model UIs focus on chat, not operations. The missing piece is a fast top-of-screen control surface that can:

- show which profiles are actually ready
- switch the machine to a target model with one click
- start and stop heavy runtimes cleanly
- trigger benchmarks without digging through terminal history
- open the backing endpoint or dashboard when you need details

On macOS, the right primitive for that is `MenuBarExtra`, not a WidgetKit-first build.

## Buttons in the menu bar app

Global actions:

- `Refresh`
- `Open Dashboard`
- `Open Latest Bench`
- `Quick Bench All`
- `Stop All`
- `Settings`
- `Help`
- `Quit`

Optional integration actions:

- zero by default
- dynamically shown only when the controller reports an available integration
- current built-in example: `Sync Droid`

Per-profile actions:

- `Activate` -- stop other running profiles and start this one
- `Start`
- `Stop`
- `Restart`
- `Bench`
- `Open`

`Activate` is the key workflow for laptops. It gives you one-click model switching without leaving old heavyweight runtimes resident.

`Settings` and `Help` now open inside the menu interface itself as a right-side inspector, so they stay attached to the menu bar surface instead of spawning detached desktop windows.

## Controller API contract

The app expects a controller base URL, defaulting to:

- `http://127.0.0.1:8877`

Endpoints used today:

- `GET /api/status`
- `GET /api/integrations`
- `GET /api/benchmark/status`
- `POST /api/start`
- `POST /api/stop`
- `POST /api/restart`
- `POST /api/switch`
- `POST /api/stop-all`
- `POST /api/integrations/run`
- `POST /api/benchmark/start`

`POST /api/sync-droid` still exists in the current Python adapter as a backward-compatible alias, but the app no longer depends on that hard-coded route.

A backend can be considered compatible if it returns the same basic JSON shape for profile status, exposes an `integrations` array when optional external actions are available, and supports the lifecycle actions above.

## Build

```bash
swift test
./Scripts/clean-install.sh
```

That installs a fresh copy at:

- `~/Applications/Model Switchboard.app`

and removes the old legacy `ModelSwitchboard.app` bundle name so you do not keep launching a stale app by accident.

For iterative development:

```bash
./Scripts/run-dev.sh
```

## Included example controller

This repo also ships a generic reference controller under `Controller/`.

It includes:

- a Python control plane
- a branded Swift launcher for `launchd`
- a local benchmark harness
- a SwiftBar companion script
- an example custom-command profile

## Why not WidgetKit first?

WidgetKit is still useful if you want a desktop widget or Notification Center glance view, but it is not the best starting point for a fast model-switching UX. For top-of-screen interaction, `MenuBarExtra` is the correct foundation. The menu bar app can later share state and actions with a WidgetKit extension if a desktop widget becomes worth building.

## Open source posture

Yes, this should live in a repo and be open-sourceable.

The right way to make it reusable is not to hard-code one person’s Python paths. The right way is:

- keep the app generic
- document the controller contract
- treat external tools like Droid as optional integrations, not required features
- ship one backend adapter as an example
- let other people plug in their own runtime stack

That is what this repo is structured to support.
