# Model Switchboard

A native macOS menu bar app for operating local model runtimes.

`Model Switchboard` is model-agnostic. It talks to a controller API; the controller can launch `llama.cpp`, MLX, Ollama, vLLM, or any other compatible runtime.

## Editions

This repo ships two editions from one codebase:

- `Model Switchboard` -- the lightweight base edition
- `Model Switchboard Plus` -- the expanded edition with advanced operations

Profiles stay in the base edition. They are the source of truth for model launches, so they are not treated as an optional power-user feature.

Feature split:

- Base
  - profile list
  - `Activate`, `Start`, `Stop`, `Restart`
  - `Refresh`, `Stop All`
  - attached `Settings` and `Help`
  - launch-at-login toggle
  - live `model-profiles` and controller-root discovery
  - widget
- Plus
  - everything in Base
  - `Benchmark All` and `Reopen Last`
  - per-profile `Benchmark`
  - in-app benchmark panel with CSV export
  - CPU and GPU utilization badges in the header
  - optional controller integrations such as `Sync Droid`
  - plus widget branding

## Purpose

The app provides a fast operations surface that can:

- show which profiles are actually ready
- switch the machine to a target model with one click
- start and stop heavy runtimes cleanly
- open the backing endpoint when you need details

The Plus edition adds benchmark and integration controls without increasing base-edition surface area.

## Buttons in the menu bar app

Global actions:

- `Refresh`
- `Stop All`
- `Benchmark All` (Plus)
- `Reopen Last` (Plus)
- `Settings`
- `Help`
- `Quit`

Per-profile actions:

- `Activate` -- stop other running profiles and start this one
- `Start`
- `Stop`
- `Restart`
- `Benchmark` (Plus)

`Activate` is the primary laptop workflow: switch to one model and stop the rest.

`Settings` and `Help` open as attached inspector panels, not detached desktop windows.

`Settings` also includes:

- a `Launch At Login` toggle backed by macOS `ServiceManagement`
- the live `model-profiles` path reported by the controller
- one-click actions to open the profiles folder or controller root in Finder

Model locations are defined in controller profile manifests, not in app preferences.

In `Model Switchboard Plus`, benchmark controls and integration actions stay in the main surface; benchmark results are viewable in-app and exportable to CSV.

## Raycast

Raycast users have two paths:

1. the app should appear as a normal macOS application after install
2. keyboard-first operators should also get direct scriptable actions without opening the menu

This repo supports both:

- `Scripts/install.sh` explicitly registers the app with Launch Services and forces a Spotlight import so Raycast can discover it faster
- `Scripts/model-switchboardctl` provides a tiny controller CLI and supports `MODEL_SWITCHBOARD_VARIANT=base|plus`
- `Integrations/Raycast/Script Commands/` contains lightweight Script Commands for status, opening the profiles folder, stopping all models, and running quick benchmarks

If Finder shows `.app`, that is a Finder preference (`AppleShowAllExtensions`), not a bundle naming issue.

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

A backend is compatible if it returns the same profile-status JSON shape, exposes optional `integrations`, and supports the lifecycle actions above.

## Benchmark outputs

The bundled controller benchmark harness always writes both machine-readable and human-readable outputs under:

- `Controller/benchmark-results/`

Each completed run produces:

- `benchmark-YYYYMMDD-HHMMSS.json`
- `benchmark-YYYYMMDD-HHMMSS.md`
- `latest.json`
- `latest.md`

The Plus benchmark panel reads `latest.json` and renders the latest run in-app. `Export CSV` writes a portable report from the current latest run.

## Version

- `1.0.0`

The current release version lives in:

- `VERSION`

## Install

Base edition:

```bash
./Scripts/install.sh
```

or explicitly:

```bash
APP_VARIANT=base ./Scripts/install.sh
```

Plus edition:

```bash
APP_VARIANT=plus ./Scripts/install.sh
```

That installs fresh copies at:

- `~/Applications/Model Switchboard.app`
- `~/Applications/Model Switchboard Plus.app`

The installer also removes the old `ModelSwitchboard.app` bundle name to avoid stale launches.

## Uninstall

```bash
./Scripts/uninstall.sh
```

That removes the app from:

- `~/Applications`
- `dist/`

and clears the most obvious app-side preference and widget container files.

## Build

```bash
swift test
./Scripts/build-app.sh
```

That builds the base release app bundle at:

- `dist/Model Switchboard.app`

Plus edition:

```bash
APP_VARIANT=plus ./Scripts/build-app.sh
```

That builds:

- `dist/Model Switchboard Plus.app`

The Xcode build script regenerates `.xcodeproj` from `project.yml` before building.

## DMG

```bash
./Scripts/build-dmg.sh
```

That produces the base DMG:

- `dist/Model-Switchboard-1.0.0.dmg`

Plus edition:

```bash
APP_VARIANT=plus ./Scripts/build-dmg.sh
```

That produces:

- `dist/Model-Switchboard-Plus-1.0.0.dmg`

For local verification:

```bash
./Scripts/verify-distribution.sh
```

Plus verification:

```bash
APP_VARIANT=plus ./Scripts/verify-distribution.sh
```

This verifies app bundle structure and code signature. Gatekeeper checks are skipped for local ad hoc builds.

## Release stance

For GitHub distribution:

1. a Developer ID-signed app
2. a notarized `.dmg`
3. a GitHub Release that points users to the DMG

This repo builds DMGs locally; public releases should be signed and notarized.

This repo now includes:

- `Scripts/sign-and-notarize-dmg.sh`
- `.github/workflows/release.yml`

The release workflow signs, notarizes, verifies, and uploads both editions.

The GitHub release workflow expects these secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_DEVELOPER_IDENTITY`
- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_API_KEY_ID`
- `APPLE_NOTARY_API_ISSUER_ID`

## Iterative development

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

## Widget note

WidgetKit distribution follows the host app: users install and launch the containing app once before the widget appears in the gallery.

## Open source posture

To keep this reusable:

- keep the app generic
- document the controller contract
- treat external tools like Droid as optional integrations, not required features
- ship one backend adapter as an example
- let other people plug in their own runtime stack
