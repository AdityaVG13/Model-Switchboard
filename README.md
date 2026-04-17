<div align="center">

# Model Switchboard

**Flip between local LLM runtimes from your menu bar. One click to activate. One click to stop everything.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)](VERSION)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square)](#requirements)
[![Swift](https://img.shields.io/badge/swift-6.0-orange?style=flat-square)](Package.swift)

<br>

<img src="Resources/Brand/screenshot-base.jpg" alt="Model Switchboard menu bar panel" width="520">

</div>

<br>

Running local models on an Apple Silicon Mac usually means a sprawl of terminal windows, half-remembered launch scripts, and no clean way to see what's actually running. Model Switchboard puts `llama.cpp`, MLX, Ollama, vLLM, or any custom launcher behind one menu bar panel. Click **Activate** on a profile, every other model stops, the one you picked comes up at an OpenAI-compatible endpoint. No terminals.

It's runtime-agnostic. It ships with a reference controller, but talks to any backend that implements the documented HTTP contract.

---

<img align="right" width="420" src="Resources/Brand/screenshot-base.jpg" alt="Base edition panel">

### One click to switch models

`Activate` stops every other running profile and brings the chosen one up — no more forgetting to `kill -9` a 24 GB process before starting the next one.

Profiles are marked *ready* only after a real health check passes. `/v1/models` by default, or a custom HTTP probe. No "green dot" lies.

Native SwiftUI and `MenuBarExtra`. No Electron, no bundled inference engine, no resident background worker pegging your CPU.

<br clear="right">

---

<img align="left" width="420" src="Resources/Brand/screenshot-plus.jpg" alt="Plus edition with header utilization and Sync Droid">

### Plus edition adds the numbers

**CPU and GPU utilization** live in the header so you know what your machine is doing without dropping into Activity Monitor.

**Benchmark All** runs the whole fleet, **Reopen Last** jumps back to what you had up, and **optional integrations** like `Sync Droid` keep your external tooling in sync with whatever's currently loaded — without cluttering the base surface if you don't need it.

<br clear="left">

---

<img align="right" width="420" src="Resources/Brand/screenshot-benchmark.jpg" alt="In-app Benchmarks panel">

### Benchmarks in the app, not a spreadsheet

The in-app panel reads the latest run and shows **TTFT, Decode, E2E, RSS** per profile in one place.

Tap **Export CSV** and you have a portable report. Results land as both JSON and Markdown under `Controller/benchmark-results/` so they're easy to diff, commit, or feed to another tool.

<br clear="right">

---

## Base vs Plus

Same codebase, two apps. Pick at install time. They live side by side as **Model Switchboard.app** and **Model Switchboard Plus.app** under `~/Applications/`.

| | Base | Plus |
|---|:---:|:---:|
| Profile list with live status | Yes | Yes |
| `Activate` / `Start` / `Stop` / `Restart` | Yes | Yes |
| `Refresh` / `Stop All` | Yes | Yes |
| `Launch At Login` + attached Settings / Help | Yes | Yes |
| CPU / GPU utilization badges | — | Yes |
| `Benchmark All` + per-profile `Benchmark` | — | Yes |
| In-app Benchmarks panel + CSV export | — | Yes |
| `Reopen Last` | — | Yes |
| Optional integrations (`Sync Droid`, …) | — | Yes |

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon recommended — Intel Macs run the app fine, but MLX models require Apple Silicon
- A running **controller**. This repo ships a reference controller under `Controller/`; any HTTP server implementing the [controller contract](SETUP.md#controller-api-contract) works

---

## Install

**Signed DMG (recommended).** From the [latest release](https://github.com/AdityaVG13/Model-Switchboard/releases/latest), grab `Model-Switchboard-<version>.dmg` or `Model-Switchboard-Plus-<version>.dmg`. Open, drag to `Applications`, launch.

**From source.**

```bash
git clone https://github.com/AdityaVG13/Model-Switchboard.git
cd Model-Switchboard
./Scripts/install.sh                   # Base
APP_VARIANT=plus ./Scripts/install.sh  # Plus
```

The installer places a fresh build under `~/Applications/`, registers it with Launch Services, and forces a Spotlight import so Raycast and Alfred pick it up immediately.

---

## First run

Model Switchboard is the control surface — it doesn't run models itself. You need a controller that knows how to launch and health-check them.

1. **Install the reference controller:**
   ```bash
   ./Controller/install-model-switchboard-controller.sh
   ```
2. **Drop a profile manifest** into `~/.model-switchboard/model-profiles/` (the exact path is shown in `Settings`). A minimal `llama.cpp` example:
   ```env
   DISPLAY_NAME=Qwen 3.5 35B Local
   RUNTIME=llama.cpp
   MODEL_PATH=/path/to/model.gguf
   PORT=8080
   REQUEST_MODEL=qwen35-local
   SERVER_MODEL_ID=qwen35-local
   ```
3. **Open the menu bar icon** — your profile appears. Click **Activate**.

Using your own runtime or launcher? Any backend that honors the controller HTTP contract works. MLX, Ollama, vLLM, and custom-command examples live in [SETUP.md](SETUP.md).

---

## Documentation

All of the deeper material is in one place so this README stays skimmable:

- **[SETUP.md](SETUP.md)** — profile formats, supported runtimes, health checks, controller API contract, build-from-source flow, release pipeline, Raycast power-user notes, troubleshooting.

The app's **Help** button opens the same doc.

---

## Contributing

PRs, issues, and profile recipes are welcome. Ground rules that keep the project reusable:

- Keep the app generic. Runtime-specific behavior belongs in the controller or a profile manifest.
- The controller HTTP contract is the stability boundary — additive changes only.
- External tools (e.g. Factory Droid) stay **optional integrations**, never required features.
- Ship a runnable example with any new adapter.

Before opening a PR: `swift test && ./Scripts/check-cycles.py && ./Scripts/build-app.sh`.

---

## License

[MIT](LICENSE) © 2026 AdityaVG13

---

<div align="center">

### Support the project

Model Switchboard is a solo side project, open-sourced for free. If it saves you time flipping between local models, a small tip helps cover the API and tooling bills that keep it moving forward.

<a href="https://ko-fi.com/AdityaVG13">
  <img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-FF5E5B?logo=ko-fi&logoColor=white&style=for-the-badge" alt="Support on Ko-fi">
</a>

</div>
