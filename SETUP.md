# Setup ModelSwitchboard

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

## Supported runtime styles

### `llama.cpp`
Best default for quantized GGUF models on Apple Silicon.

Typical fields:

- `RUNTIME=llama.cpp`
- `MODEL_PATH` or `MODEL_FILE`
- `PORT`
- `REQUEST_MODEL`
- `SERVER_MODEL_ID`

### `mlx`
Best when you have an MLX-native converted model and want very strong Apple-local throughput.

Typical fields:

- `RUNTIME=mlx`
- `MODEL_DIR` or `MODEL_REPO`
- `PORT`
- `REQUEST_MODEL`

### `custom` or `command`
Best when the model is started by some other launcher or wrapper.

Typical JSON example:

```json
{
  "DISPLAY_NAME": "My Custom Server",
  "RUNTIME": "custom",
  "START_COMMAND": "/absolute/path/to/start-my-server.sh",
  "BASE_URL": "http://127.0.0.1:8099/v1",
  "HEALTHCHECK_MODE": "http-200",
  "HEALTHCHECK_URL": "http://127.0.0.1:8099/health",
  "REQUEST_MODEL": "my-local-model",
  "SERVER_MODEL_ID": "my-local-model"
}
```

Keep the schema stable. Path layout can vary by repo.

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

- the menu refresh loop stops when the menu window disappears
- the visible footer clock only updates while the menu is open
- the menu bar hover text is computed from current status, not from a resident background worker
- the widget refreshes on a simple timeline instead of running its own always-on helper

Most memory/thermal load should remain in runtimes, not the operator UI.
