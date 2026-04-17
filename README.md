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
- `Dashboard`
- `Latest Bench`
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

`Settings` and `Help` now open inside the menu interface itself as an attached inspector, so they stay attached to the menu bar surface instead of spawning detached desktop windows.

`Settings` also includes:

- a `Launch At Login` toggle backed by macOS `ServiceManagement`
- the live `model-profiles` path reported by the controller
- one-click actions to open the profiles folder or controller root in Finder

That matters because model locations are defined in controller profile manifests, not in the app itself.

## Raycast

Raycast users should have two clean paths:

1. the app should appear as a normal macOS application after install
2. keyboard-first operators should also get direct scriptable actions without opening the menu

This repo now supports both:

- `Scripts/install.sh` explicitly registers the app with Launch Services and forces a Spotlight import so Raycast can discover it faster
- `Scripts/model-switchboardctl` provides a tiny controller CLI
- `Integrations/Raycast/Script Commands/` contains lightweight Script Commands for status, opening the profiles folder, stopping all models, and running quick benchmarks

If Finder still shows `.app` on your machine, that is a global Finder preference issue, not an app bundle naming issue. When `AppleShowAllExtensions` is enabled, Finder will keep showing bundle extensions.

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

## Version

- `1.0.0`

The current release version lives in:

- `VERSION`

## Install

For local development or direct install:

```bash
./Scripts/install.sh
```

That installs a fresh copy at:

- `~/Applications/Model Switchboard.app`

and removes the old legacy `ModelSwitchboard.app` bundle name so you do not keep launching a stale app by accident.

Compatibility alias:

```bash
./Scripts/clean-install.sh
```

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

That builds a release app bundle at:

- `dist/Model Switchboard.app`

The Xcode build script always regenerates the `.xcodeproj` from `project.yml` first. That avoids the stale-project problem where new Swift files compile in SwiftPM but never make it into the packaged app.

## DMG

```bash
./Scripts/build-dmg.sh
```

That produces:

- `dist/Model-Switchboard-1.0.0.dmg`

For local verification:

```bash
./Scripts/verify-distribution.sh
```

That always verifies the app bundle structure and code signature. Gatekeeper checks are skipped automatically for local ad hoc builds and are enforced once you sign with a real Developer ID identity.

## Release stance

For GitHub distribution, the right default is:

1. a Developer ID-signed app
2. a notarized `.dmg`
3. a GitHub Release that points users to the DMG

Why:

- Apple recommends distributing outside the Mac App Store using a signed distribution container and notarizing that container
- menu bar apps on GitHub commonly ship as DMGs
- the widget is part of the containing app, not a separate download

The current repo now builds the DMG locally. For a public release, the next step is signing and notarization.

This repo now includes both:

- `Scripts/sign-and-notarize-dmg.sh`
- `.github/workflows/release.yml`

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

## Why not WidgetKit first?

WidgetKit is still useful if you want a desktop widget or Notification Center glance view, but it is not the best starting point for a fast model-switching UX. For top-of-screen interaction, `MenuBarExtra` is the correct foundation. The menu bar app can later share state and actions with a WidgetKit extension if a desktop widget becomes worth building.

Also, WidgetKit distribution follows the host app. Apple requires people to install the containing app and launch it at least once before the widget appears in the gallery.

## Future updates

Once GitHub release packaging is stable, the natural next step is `Sparkle` for in-app updates. That is the standard open-source macOS path for apps distributed outside the App Store.

## Open source posture

Yes, this should live in a repo and be open-sourceable.

The right way to make it reusable is not to hard-code one person’s Python paths. The right way is:

- keep the app generic
- document the controller contract
- treat external tools like Droid as optional integrations, not required features
- ship one backend adapter as an example
- let other people plug in their own runtime stack

That is what this repo is structured to support.
