# Model Switchboard — Setup & Reference

Everything you need beyond the README's quickstart. This is also what the app's **Help** button opens.

## Table of contents

- [The operating model](#the-operating-model)
- [One central folder](#one-central-folder)
- [Accepted profile formats](#accepted-profile-formats)
- [Supported runtime styles](#supported-runtime-styles)
- [How detection works](#how-detection-works)
- [What is standard on a Mac](#what-is-standard-on-a-mac)
- [Why JSON is the right next step](#why-json-is-the-right-next-step)
- [Resource profile](#resource-profile)
- [Controller API contract](#controller-api-contract)
- [Benchmark artifacts](#benchmark-artifacts)
- [Build from source](#build-from-source)
- [Release pipeline](#release-pipeline)
- [Raycast and power users](#raycast-and-power-users)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)

---

## The operating model

`ModelSwitchboard` is the control surface, not the runtime.

There are three layers:

1. A native macOS UI layer
   - menu bar app via `MenuBarExtra`
   - desktop / Notification Center widget via `WidgetKit`
2. A controller API
   - profile discovery
   - lifecycle actions
   - optional integrations
3. Runtime adapters
   - `llama.cpp`
   - `mlx_lm.server`
   - `ollama`
   - `vLLM`
   - custom shell scripts
   - anything else that can be launched and health-checked

The app only needs a controller URL. The controller discovers profiles, launches runtimes, and reports health.

This repo includes one generic reference implementation under `Controller/`. You can use it directly or replace it with your own backend that exposes the same HTTP contract.

## One central folder

A practical adapter layout is:

- `<adapter-root>/model-profiles`

That folder is the source of truth. Add one manifest per model.

## Accepted profile formats

The example adapter accepts both:

- `*.env`
- `*.json`

Use `.env` for shell-style configuration. Use `.json` for structured, tool-agnostic config.

Strict example manifests live under `Controller/model-profiles/examples/`.

Every profile must resolve to a unique endpoint. If two profiles share the same `HOST:PORT` or `BASE_URL`, activation and status attribution become ambiguous, so the controller doctor treats that as a profile error.

## Supported runtime styles

### `llama.cpp`
Best default for quantized GGUF models on Apple Silicon.

Typical fields:

- `RUNTIME=llama.cpp`
- `MODEL_PATH` or `MODEL_FILE` with `MODEL_ROOT`
- `SERVER_BIN` or `LLAMA_SERVER_BIN` if `llama-server` is not already on `PATH`
- `PORT`
- `REQUEST_MODEL`
- `SERVER_MODEL_ID`

### `mlx`
Best when you have an MLX-native converted model and want very strong Apple-local throughput.

Typical fields:

- `RUNTIME=mlx`
- `MODEL_DIR` or `MODEL_REPO`
- `SERVER_BIN` or `MLX_SERVER_BIN` if `mlx_lm.server` is not already on `PATH`
- `PORT`
- `REQUEST_MODEL`

### `rvllm-mlx`
Best when you want to launch an OpenAI-compatible MLX server from a dedicated binary.

Typical fields:

- `RUNTIME=rvllm-mlx`
- `SERVER_BIN`
- `MODEL_DIR`
- `PORT`
- `REQUEST_MODEL`
- `SERVER_MODEL_ID`

### `vllm-mlx`
Best current speed lane for MLX model directories on Apple Silicon.

Typical fields:

- `RUNTIME=vllm-mlx`
- `SERVER_BIN` or `VLLM_MLX_BIN` if `vllm-mlx` is not already on `PATH`
- `MODEL_DIR` or `MODEL_REPO`
- `PORT`
- `REQUEST_MODEL`
- `SERVER_MODEL_ID`
- optional tuning fields: `MAX_TOKENS`, `MAX_REQUEST_TOKENS`, `GPU_MEMORY_UTILIZATION`, `CACHE_MEMORY_PERCENT`, `PREFILL_STEP_SIZE`, `ENABLE_TOOL_CALLS`, `TOOL_CALL_PARSER`

### Universal launchers
Best when the model is owned by another runtime, desktop app, daemon, or wrapper.

Model Switchboard now uses three launch modes:

- `adapter`: known runtimes where the controller builds the command (`llama.cpp`, `mlx`, `rvllm-mlx`, `vllm-mlx`, `ollama`, `vllm`, `sglang`, `tgi`, `llama-cpp-python`).
- `command`: profile-owned `START_COMMAND`, optional `STOP_COMMAND`, and readiness.
- `external`: an already-running OpenAI-compatible endpoint such as LM Studio, Jan, LocalAI, or a manually launched server.

Named command and generic-binary profiles can still use runtime ids such as `ddtree-mlx`, `turboquant`, `mlx-vlm`, `mlx-omni-server`, `mistral.rs`, `mlc-llm`, `lightllm`, `fastchat`, `openllm`, `nexa`, `exllamav2`, `aphrodite`, and `lmdeploy`; they retain their real runtime label instead of displaying as custom. Use `LAUNCH_MODE=external` when a named runtime is already running outside Model Switchboard. Every profile status includes `runtime_label`, `runtime_tags`, and `launch_mode`. Add custom tags with `RUNTIME_TAGS="coding q8 long-context"`.

Generic JSON example:

```json
{
  "DISPLAY_NAME": "My Custom Server",
  "RUNTIME": "command",
  "START_COMMAND": "/absolute/path/to/start-my-server.sh",
  "STOP_COMMAND": "curl -fsS -X POST http://127.0.0.1:8099/shutdown || true",
  "BASE_URL": "http://127.0.0.1:8099/v1",
  "HEALTHCHECK_MODE": "http-200",
  "HEALTHCHECK_URL": "http://127.0.0.1:8099/health",
  "REQUEST_MODEL": "my-local-model",
  "SERVER_MODEL_ID": "my-local-model"
}
```

Generic binary example for runtimes without a first-class adapter:

```json
{
  "DISPLAY_NAME": "Any Local Server",
  "RUNTIME": "tabbyapi",
  "SERVER_BIN": "/absolute/path/to/server",
  "SERVER_ARGS_JSON": ["--host", "127.0.0.1", "--port", "5000", "--model", "/models/model"],
  "BASE_URL": "http://127.0.0.1:5000/v1",
  "REQUEST_MODEL": "local-model",
  "SERVER_MODEL_ID": "local-model"
}
```

See [Controller/RUNTIME_SUPPORT.md](Controller/RUNTIME_SUPPORT.md) for the full runtime matrix and examples.

Keep the schema stable. Path layout can vary by repo.

The reference macOS launcher is intentionally strict:

- it does not guess Homebrew paths, repo-local runtime builds, or personal directories
- binaries come from the profile manifest or `PATH`
- model locations come from the profile manifest

## How detection works

For each profile it does this:

1. Read the managed PID file if present.
2. If the PID is stale, clear it.
3. If no managed PID exists, fall back to checking whether the configured port has a listener.
4. Run the configured health check.

Supported health-check modes:

- `openai-models`
  - default for `llama.cpp` and `mlx`
  - probes `/v1/models`
  - verifies the expected model ID is present
- `http-200`
  - generic HTTP readiness
  - considers the profile ready when the configured URL returns success
- `disabled`
  - only use this when you truly cannot probe readiness
  - process state may still be visible, but endpoint health is not verified

The UI is launcher-agnostic as long as each profile defines startup and readiness checks.

## What is standard on a Mac

For Apple Silicon local inference, common stacks are:

- `llama.cpp` with Metal
- `MLX` / `mlx_lm.server`
- `rvllm-mlx`

Other tools usually fit into one of these buckets:

- `Ollama`
  - convenience packaging and model management around a local runtime
- `LM Studio`
  - GUI-first local model UX built around local backends
- `Jan`, `Open WebUI`, `SoulForge`, `vLLM Studio`
  - client UX, orchestration, or alternate serving layers
- `vLLM`
  - strong on CUDA/Linux, not the default serious choice on Apple Silicon laptops

A high-performance macOS stack is usually:

- `llama.cpp` for GGUF
- `MLX` for MLX-native models
- OpenAI-compatible endpoints for tool interoperability

## Why JSON is the right next step

JSON is usually easier to operate than raw env files for shared setups.

Reasons:

- explicit structure
- easier schema validation later
- easier editor tooling
- easier runtime-agnostic fields such as `START_COMMAND`, `BASE_URL`, and `HEALTHCHECK_MODE`
- easier future migration to a full profile registry

The current adapter keeps `.env` support for backward compatibility.

## Resource profile

`ModelSwitchboard` itself is intentionally light.

- native SwiftUI app
- native WidgetKit extension
- no Electron
- no embedded browser runtime
- no bundled inference engine
- no constant high-frequency polling

Design choices that keep the app light:

- the controller refresh loop uses an adaptive low-frequency cadence instead of aggressive constant polling
- the visible footer clock only updates while the menu is open
- the menu bar hover text is derived from the same lightweight controller snapshot the shell uses
- the widget refreshes on a simple timeline instead of running its own always-on helper

Most memory/thermal load should remain in runtimes, not the operator UI.

---

## Controller API contract

The app expects a controller base URL, defaulting to `http://127.0.0.1:8877`.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/status` | Profile + readiness snapshot |
| `GET` | `/api/integrations` | Optional integration manifest (Plus) |
| `GET` | `/api/benchmark/status` | Current benchmark run state (Plus) |
| `POST` | `/api/start` | Start a profile |
| `POST` | `/api/stop` | Stop a profile |
| `POST` | `/api/restart` | Restart a profile |
| `POST` | `/api/switch` | Stop others, start target (the `Activate` path) |
| `POST` | `/api/stop-all` | Stop every managed profile |
| `POST` | `/api/integrations/run` | Trigger an optional integration (Plus) |
| `POST` | `/api/benchmark/start` | Run benchmark(s) (Plus) |

Any backend that returns the same profile-status JSON shape and supports these lifecycle actions is compatible. See `Controller/contracts.py` for the exact response shapes.

## Benchmark artifacts

The reference benchmark harness writes both machine-readable and human-readable outputs to:

- `Controller/benchmark-results/`

Each completed run produces:

- `benchmark-YYYYMMDD-HHMMSS.json`
- `benchmark-YYYYMMDD-HHMMSS.md`
- `latest.json`
- `latest.md`

The Plus panel reads `latest.json`. **Export CSV** writes a portable report from the current latest run.

---

## Build from source

```bash
# Run tests
swift test

# Iterative dev (launches a debug build)
./Scripts/run-dev.sh

# Release build — produces dist/Model Switchboard.app
./Scripts/build-app.sh
APP_VARIANT=plus ./Scripts/build-app.sh   # Plus edition

# DMG — produces dist/Model-Switchboard-<version>.dmg
./Scripts/build-dmg.sh
APP_VARIANT=plus ./Scripts/build-dmg.sh   # Plus DMG

# Verify an installed copy
./Scripts/verify-installed-app.sh
```

Or via `make`:

```bash
make test       # swift test
make app        # build-app.sh
make dmg        # build-dmg.sh
make install    # install.sh
make uninstall  # uninstall.sh
```

The Xcode build path regenerates `ModelSwitchboard.xcodeproj` from `project.yml` via XcodeGen before building, so you never hand-edit the project file.

## Release pipeline

For GitHub distribution:

1. a Developer ID-signed app
2. a notarized `.dmg`
3. a GitHub Release that points users to the DMG

This repo builds DMGs locally; public releases should be signed and notarized.

Included:

- `Scripts/release-preflight.sh`
- `Scripts/bump-version.py`
- `Scripts/sign-and-notarize-dmg.sh`
- `.github/workflows/release.yml`

The release workflow signs, notarizes, verifies, and uploads both editions when either:

- a `v*` tag is pushed
- a commit on `main` changes `VERSION`

That means the normal maintainer flow can be:

```bash
python3 Scripts/bump-version.py patch   # or minor / major / x.y.z
git push origin main
```

GitHub Actions will create or update the matching `v<version>` release for that commit. Required repo secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_DEVELOPER_IDENTITY`
- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_API_KEY_ID`
- `APPLE_NOTARY_API_ISSUER_ID`

Recommended local preflight before push/tag:

```bash
./Scripts/release-preflight.sh
```

Manual release checklist:

- install the built Base and Plus apps side by side
- toggle `Launch At Login` in one edition and confirm only that edition remains in macOS Login Items
- run `APP_VARIANT=base ./Scripts/verify-installed-app.sh`
- run `APP_VARIANT=plus ./Scripts/verify-installed-app.sh`

---

## Raycast and power users

Raycast users have two paths:

1. The app appears as a normal macOS application after install.
2. Keyboard-first operators can also call scriptable actions without opening the menu.

This repo supports both:

- `Scripts/install.sh` explicitly registers the app with Launch Services and forces a Spotlight import so Raycast can discover it faster.
- `Scripts/model-switchboardctl` provides a tiny controller CLI, selectable per edition via `MODEL_SWITCHBOARD_VARIANT=base|plus`.
- `Integrations/Raycast/Script Commands/` contains Script Commands for status, opening the profiles folder, stopping all models, and running quick benchmarks.

If Finder shows `.app` extensions, that is the macOS `AppleShowAllExtensions` Finder preference, not a bundle naming issue.

---

## Troubleshooting

**The app doesn't appear in Spotlight or Raycast.**
Run `./Scripts/install.sh` — it registers the bundle with Launch Services and forces a Spotlight import. If the old `ModelSwitchboard.app` name is still cached, the installer removes it automatically.

**A profile shows "Not Running" even though I can `curl` the endpoint.**
The default health check for `llama.cpp` and `mlx` profiles probes `/v1/models` and verifies the expected model ID is present. If your server returns a different id, set `SERVER_MODEL_ID` in the profile to match, or switch the profile to `HEALTHCHECK_MODE=http-200` for a looser check.

**`Activate` doesn't kill the previously running model.**
Each runtime is tracked by a managed PID file. If you started the process outside Model Switchboard (e.g. a terminal `llama-server` invocation), the controller doesn't own that PID. Stop the outside process manually, then use `Activate`.

**The widget doesn't show up in the widget gallery.**
See [Known limitations](#known-limitations) — the widget extension is bundled correctly but only registers reliably with a Developer-ID-signed build.

**Benchmarks panel is empty or cooldown won't clear.**
The Plus panel reads `Controller/benchmark-results/latest.json`. Delete it to reset the panel, or run `Benchmark All` once to regenerate.

**Controller port `8877` is already in use.**
The default can be overridden when the controller starts. If you changed it, also update the controller URL in the app's `Settings` panel.

**Installed-app verification fails in headless or restricted Apple Events environments.**
Run `MSW_VERIFY_UI=0 ./Scripts/verify-installed-app.sh` to execute lifecycle/API checks without UI automation.

---

## Known limitations

**Desktop / Notification Center widget requires a Developer-ID-signed build.**
The widget target (`ModelSwitchboardWidget`) is real, embedded into the app bundle at `Contents/PlugIns/ModelSwitchboardWidget.appex`, and wired through `project.yml`. However, local installs from `./Scripts/install.sh` ad-hoc sign the bundle (`codesign --sign -`), and ad-hoc-signed widget extensions are not reliably registered by WidgetKit's gallery. The widget begins to register once the app is installed from a Developer ID-signed, notarized DMG (i.e. the GitHub Release build). If you want to verify on a local build, try:

```bash
pluginkit -a "$HOME/Applications/Model Switchboard.app/Contents/PlugIns/ModelSwitchboardWidget.appex"
killall chronod cfprefsd 2>/dev/null || true
open -a "Model Switchboard"
```

Then wait ~60 seconds and check the Widget gallery. Results vary across macOS versions.

**Widget note.** WidgetKit distribution follows the host app: users install and launch the containing app once before the widget appears in the gallery — once registration actually succeeds.

---

## Open source posture

To keep this reusable:

- keep the app generic
- document the controller contract
- treat external tools like Droid as optional integrations, not required features
- ship one backend adapter as an example
- let other people plug in their own runtime stack
