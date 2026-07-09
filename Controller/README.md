# ModelSwitchboard Controller

This directory contains the local control plane used by the app.

## What It Does

- Starts and stops local model runtimes
- Reports running and ready status over HTTP
- Exposes benchmark status and optional integrations
- Writes a shared cache file for the app and widget
- Runs under `launchd` via a small Swift launcher so macOS does not display the service as `python3`

## Key Files

- `modelctl.py` -- stable CLI/HTTP entrypoint (thin facade over `msctl/`)
- `msctl/` -- controller implementation package (profiles, doctor, API server, CLI, runtimes)
- `ModelSwitchboardController.swift` -- lightweight launcher used by `launchd`
- `install-model-switchboard-controller.sh` -- installs the background service
- `start-model-mac.sh` -- runtime launcher for profile-backed model servers
- `benchmark-local-models.py` -- local benchmark harness
- `sync-droid-local-models.py` -- optional Droid model sync helper
- `swiftbar/local-models.15s.sh` -- optional SwiftBar integration
- `model-profiles/examples/custom-command-profile.json` -- example of a generic custom runtime profile

## Operating Model

The controller reads profiles from `model-profiles`. Each profile defines launch and endpoint settings. The app remains model-agnostic because it only calls the controller API.

When a profile is activated through the switch action, the controller records it as the active profile in `run/active-profile`. The background service checks that active profile every 30 seconds and restarts it if both the process and health check are gone. This covers native runtime crashes without keeping a dead overnight job hidden behind a stale PID.

The controller CLI has an agent-facing doctor and robot surface:

```bash
./modelctl.py triage --json
./modelctl.py capabilities --json
./modelctl.py robot-docs guide
./modelctl.py start <profile> --dry-run --json
./modelctl.py stop <profile> --json
./modelctl.py restart <profile> --plan --json
./modelctl.py switch <profile> --dry-run --json
./modelctl.py stop-all --dry-run --json
./modelctl.py doctor --json
./modelctl.py doctor health --json
./modelctl.py doctor capabilities --json
./modelctl.py doctor robot-docs
./modelctl.py doctor --dry-run --fix --json
./modelctl.py doctor undo <run-id> --json
```

`triage --json` is the one-call entrypoint for agents: it returns health, profile names, recommended commands, and exit-code meanings. `capabilities --json` describes the command contract, mutating surfaces, aliases, JSON support, and stdout/stderr contract. Mutating profile commands (`start`, `stop`, `restart`, `switch`, and `stop-all`) support `--dry-run`/`--plan` and `--json`; JSON mode returns a stable envelope with the plan, execution status, captured command output, errors, and post-action status when applied. `robot-docs guide` prints paste-ready in-tool guidance. Intent aliases are accepted for common first tries: `diagnose --json` maps to `doctor --json`, `health --json` maps to `doctor health --json`, `--robot-triage` maps to `triage --json`, and `--capabilities` maps to `capabilities --json`.

`doctor` diagnoses controller reachability, LaunchAgent state, profile directory state, duplicate endpoints, invalid profile URLs, missing model sources, missing runtimes, and disabled health checks. Detect mode writes only `.doctor/runs/<run-id>/` artifacts. The only auto-fixer currently creates a missing `model-profiles` directory, records an action in `actions.jsonl`, and can be undone with `doctor undo <run-id>`.

For llama.cpp profiles, `MODEL_PATH` still wins when set. If you prefer `MODEL_FILE`, the controller now resolves model roots in this order: `MODEL_ROOT`, `MODEL_ROOT_HINT`, `~/AI/models`, then `../models` relative to `Controller/`.

## Benchmark harness

The benchmark harness is split into multiple workload shapes:

- `quick` for a fast interactive spot check from the UI
- `local` for short-latency, sustained decode, long-prompt prefill, and coding-oriented runs
- `context` for prompt-scaling checks that stress prefill separately from decode
- `coding` for practical coding-agent style prompts

Every completed run writes:

- a timestamped JSON report
- a timestamped Markdown report
- `latest.json`
- `latest.md`

All outputs are written to `Controller/benchmark-results/`. The app reads `latest.json` and can open the reports.

## Install

```bash
cd Controller
bash install-model-switchboard-controller.sh
```

To install the LaunchAgent for a different controller checkout, pass `--root`:

```bash
bash install-model-switchboard-controller.sh --root /absolute/path/to/Controller
```

That installs a per-user LaunchAgent that exposes the controller at `http://127.0.0.1:8877`.

## Uninstall

```bash
cd Controller
bash uninstall-model-switchboard-controller.sh
```
