<div align="center">

<pre>
 __  __  ___  ___  ___ _
|  \/  |/ _ \|   \| __| |
| |\/| | (_) | |) | _|| |__
|_|  |_|\___/|___/|___|____|
 _____      _____ _____ ___ _  _ ___  ___   _   ___ ___
/ __\ \    / /_ _|_   _/ __| || | _ )/ _ \ /_\ | _ \   \
\__ \\ \/\/ / | |  | || (__| __ | _ \ (_) / _ \|   / |) |
|___/ \_/\_/ |___| |_| \___|_||_|___/\___/_/ \_\_|_\___/
</pre>

***Flip between local LLM runtimes from your menu bar.***
**One click to activate. One click to stop everything.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)](VERSION)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B-lightgrey?style=for-the-badge&logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/swift-6.0-orange?style=for-the-badge&logo=swift&logoColor=white)](Package.swift)

</div>

---

Running local models on an Apple Silicon Mac usually means a sprawl of terminal windows, half-remembered launch scripts, and no clean way to see **what's actually running.** Model Switchboard puts every runtime you have — `llama.cpp`, MLX, Ollama, vLLM, or anything you can script — behind **one menu bar panel.** Click **Activate**, every other model stops, the one you picked comes up at an OpenAI-compatible endpoint.

*No terminals. No orphan processes. No "green dot" lies.*

---

<img align="right" width="420" src="Resources/Brand/screenshot-base.jpg" alt="Base edition panel">

### One click. One model running.

**`Activate` stops every other profile and brings the chosen one up.** No more forgetting to `kill -9` a 24 GB process before starting the next one.

Profiles are marked **ready** *only* after a real health check passes — `/v1/models` by default, or a custom HTTP probe. If it says green, it means green.

Built with **SwiftUI** and `MenuBarExtra`. No Electron, no bundled inference engine, no resident background worker pegging your CPU.

<br clear="right">

---

<img align="left" width="420" src="Resources/Brand/screenshot-plus.jpg" alt="Plus edition with utilization and Sync Droid">

### Plus adds the numbers.

**CPU and GPU utilization** live in the header, so you know what your machine is doing *without* dropping into Activity Monitor.

**`Benchmark All`** runs the fleet. **`Reopen Last`** jumps straight back to what you had up. **`Sync Droid`** pushes your managed profiles into Factory Droid's custom-model settings, so the model you just activated is the one Droid uses — *the first of several planned sync adapters ([see contributing](#contributing)).*

<br clear="left">

---

<img align="right" width="420" src="Resources/Brand/screenshot-benchmark.jpg" alt="In-app Benchmarks panel">

### Benchmarks in the app, not a spreadsheet.

The inline panel reads the latest run and shows **TTFT**, **Decode**, **E2E**, and **RSS** per profile in one place.

Tap **`Export CSV`** and you have a portable report. Every run lands as both JSON and Markdown under `Controller/benchmark-results/` — easy to diff, commit, or feed into another tool.

<br clear="right">

---

## Base vs Plus

*Same codebase, two apps.* Pick at install time. They live side by side as **Model Switchboard.app** and **Model Switchboard Plus.app** under `~/Applications/`.

| | Base | Plus |
|---|:---:|:---:|
| Profile list with live status | ✓ | ✓ |
| `Activate` / `Start` / `Stop` / `Restart` | ✓ | ✓ |
| `Refresh` / `Stop All` | ✓ | ✓ |
| `Launch At Login` + attached Settings / Help | ✓ | ✓ |
| CPU / GPU utilization badges | — | ✓ |
| `Benchmark All` + per-profile `Benchmark` | — | ✓ |
| In-app Benchmarks panel + CSV export | — | ✓ |
| `Reopen Last` | — | ✓ |
| `Sync Droid` and future integration adapters | — | ✓ |

---

## Requirements

- **macOS 14** (Sonoma) or later
- **Apple Silicon recommended** — Intel Macs run the app fine, but *MLX models require Apple Silicon*
- A running **controller** that exposes the [controller contract](SETUP.md#controller-api-contract). This repo ships a reference controller under `Controller/`

---

## Install

**Signed DMG (recommended).** Grab the latest from **[Releases](https://github.com/AdityaVG13/Model-Switchboard/releases/latest)**:

- `Model-Switchboard-<version>.dmg` (Base)
- `Model-Switchboard-Plus-<version>.dmg` (Plus)

Open, drag to `Applications`, launch.

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

*Model Switchboard is the control surface — it doesn't run models itself.* You need a controller that knows how to launch and health-check them.

**1. Install the reference controller:**

```bash
./Controller/install-model-switchboard-controller.sh
```

**2. Drop a profile manifest** into `~/.model-switchboard/model-profiles/` *(the exact path is shown in `Settings`).* A minimal `llama.cpp` example:

```env
DISPLAY_NAME=Qwen 3.5 35B Local
RUNTIME=llama.cpp
MODEL_PATH=/path/to/model.gguf
PORT=8080
REQUEST_MODEL=qwen35-local
SERVER_MODEL_ID=qwen35-local
```

**3. Open the menu bar icon.** Your profile appears. Click **`Activate`**.

> Using your own runtime or launcher? Any backend that honors the [controller contract](SETUP.md#controller-api-contract) works. MLX, Ollama, vLLM, and custom-command examples live in [SETUP.md](SETUP.md).

---

## Documentation

All the deeper material lives in one place so this README stays skimmable:

> **[SETUP.md](SETUP.md)** — profile formats, supported runtimes, health checks, controller API contract, build-from-source flow, release pipeline, Raycast power-user notes, troubleshooting, known limitations.

*The app's **Help** button opens the same doc.*

---

## Contributing

PRs, issues, and profile recipes are welcome. A few ground rules that keep the project reusable:

- **Keep the app generic.** Runtime-specific behavior belongs in the controller or a profile manifest.
- **The controller HTTP contract is the stability boundary** — additive changes only.
- External tools stay **optional integrations**, never required features.
- Ship a runnable example with any new adapter.

### Especially wanted: more sync adapters

**`Sync Droid` is currently Factory-Droid-specific** because that's the agent I run. The integration slot is generic — the adapter is not. **PRs that add sync adapters for other local-model terminals or agentic tools are very welcome**, including but not limited to:

- **Cursor** / **Windsurf** — push the active profile into the OpenAI-compatible provider settings
- **OpenAI Codex CLI** — update `~/.codex/config.toml` model entry
- **Zed** — update `~/.config/zed/settings.json` assistant provider
- **Continue** (`~/.continue/config.json`)
- **Aider** — point at the active endpoint
- **LM Studio** / **Ollama chat frontends** / any **OpenAI-compatible consumer**

If you build one, follow the shape of `Controller/sync-droid-local-models.py` and register it under `Controller/integrations/` so it shows up in the Plus menu automatically.

Before opening a PR:

```bash
swift test && ./Scripts/check-cycles.py && ./Scripts/build-app.sh
```

---

## License

**[MIT](LICENSE)** © 2026 AdityaVG13

---

<div align="center">

### Support the project

*Model Switchboard is a solo side project, open-sourced for free.*
If it saves you time flipping between local models, a small tip helps cover the API and tooling bills that keep it moving forward.

<a href="https://ko-fi.com/AdityaVG13">
  <img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-FF5E5B?logo=ko-fi&logoColor=white&style=for-the-badge" alt="Support on Ko-fi">
</a>

</div>
