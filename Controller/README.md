# ModelSwitchboard Controller

This directory contains the local control plane that powers the menu bar app.

## What It Does

- Starts and stops local model runtimes
- Reports running and ready status over HTTP
- Exposes benchmark status and optional integrations
- Writes a shared cache file for the app and widget
- Runs under `launchd` through a small branded Swift launcher so macOS does not surface the service as `python3`

## Key Files

- `modelctl.py` -- HTTP control plane and CLI entrypoint
- `ModelSwitchboardController.swift` -- lightweight launcher used by `launchd`
- `install-model-switchboard-controller.sh` -- installs the background service
- `start-model-dashboard.sh` -- launches the local dashboard in a browser
- `start-model-mac.sh` -- runtime launcher for profile-backed model servers
- `benchmark-local-models.py` -- local benchmark harness
- `sync-droid-local-models.py` -- optional Droid model sync helper
- `swiftbar/local-models.15s.sh` -- optional SwiftBar integration
- `model-profiles/examples/custom-command-profile.json` -- example of a generic custom runtime profile

## Operating Model

The controller reads model profiles from its sibling `model-profiles` directory. Each profile defines how a runtime should be launched and how its OpenAI-compatible endpoint should be addressed. The menu bar app remains model-agnostic because it only talks to the controller.

If you want to keep profiles elsewhere, either:

1. Run the controller from a working directory that contains your profile set.
2. Adapt the controller to accept an external profile directory override.

## Benchmark harness

The benchmark harness is intentionally split into multiple workload shapes instead of one blended score:

- `quick` for a fast interactive spot check from the UI
- `local` for short-latency, sustained decode, long-prompt prefill, and coding-oriented runs
- `context` for prompt-scaling checks that stress prefill separately from decode
- `coding` for practical coding-agent style prompts

Every completed run writes:

- a timestamped JSON report
- a timestamped Markdown report
- `latest.json`
- `latest.md`

All outputs live in `Controller/benchmark-results/`. The menu bar app opens `latest.md`.

## Install

```bash
cd Controller
bash install-model-switchboard-controller.sh
```

That installs a per-user LaunchAgent that exposes the controller at `http://127.0.0.1:8877`.

## Uninstall

```bash
cd Controller
bash uninstall-model-switchboard-controller.sh
```
