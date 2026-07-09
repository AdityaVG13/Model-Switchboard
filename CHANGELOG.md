# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added
- Recognized `llama-swap` as an external OpenAI-compatible proxy runtime, with an example profile and docs for request-driven model swapping alongside menu-bar Activate.
- Optional controller bearer-token field in Settings (and widget AppStorage) so token-protected / `--unsafe-bind` controllers work from the menu bar.
- Split the controller implementation into the `Controller/msctl/` package (`paths`, `security`, `runtimes`, `profiles`, `mutations`, `benchmarks`, `doctor`, `agent_contracts`, `web`, `cli`) while keeping `modelctl.py` as the stable CLI/import facade.

### Changed
- Extracted the controller web dashboard HTML into `Controller/web/dashboard.html` (first step toward decomposing the `modelctl.py` god file).
- Extended doctor report contracts (Python + Swift) to include `findings`, `next_steps`, and schema/version metadata the API already emitted.
- `stop-all-models.sh` now stops only PID-file-tracked processes by default; set `FORCE_ORPHANS=1` for the previous broad pgrep sweep.

### Fixed
- Serialized start/stop/switch/benchmark mutations with a process-wide lock so concurrent HTTP workers cannot interleave lifecycle actions.
- Cleared the active-profile marker and suppressed the crash-recovery watchdog at the start of Stop so intentional stops are not undone mid-flight.
- Parsed HTTP request paths without query/fragment so `/?token=…` serves the dashboard and `/api/*?…` routes match correctly; prefer `#token=` bootstrap and strip `?token=` from the address bar.
- Refused to kill port listeners based on health-check success alone; require a strong command match, and ignore short PID markers that over-match.
- Default-denied non-loopback health/model-list probes unless `ALLOW_REMOTE_HEALTHCHECK=1` is set.
- Constrained `doctor undo` run ids to a safe character set under `.doctor/runs`.
- Hardened status-cache file permissions (`0700`/`0600`).
- Built Swift controller API URLs without percent-encoding `/` in multi-segment paths, and rolled back optimistic profile UI state when an action fails.

## [1.2.0] - 2026-07-03

### Added
- Added the redesigned Switchboard panel with ready-count header, system sparklines, runtime filters, active-model hero card, and compact model rows.
- Added full-width Benchmarks and Settings side panels with design-token styling.
- Added prefill-scaling benchmark data in controller payloads and the Benchmarks panel.

### Changed
- Refreshed README screenshots and release imagery for the new panel design.
- Let the menu bar item show ready counts and added theme, accent, and side-panel preferences.

### Fixed
- Prevented stale or cached running state from rendering as live active model state.
- Avoided caching stopped state before stop verification succeeds.
- Kept failed benchmark starts from arming the benchmark cooldown.

## [1.1.7] - 2026-06-09

### Added
- Installed `model-switchboardctl` and bash/zsh/fish completions from the source installer.
- Added installer regression coverage for quiet installs, verification, and completion generation.
- Added agent-facing controller and wrapper discovery surfaces for capabilities, triage, robot docs, doctor diagnostics, and mutating-command dry-run plans.

### Changed
- Hardened the app and controller installers with help flags, quiet/no-gum modes, preflight checks, atomic locks, install verification, and final uninstall guidance.
- `model-switchboardctl --json` output for mutating commands now uses structured result envelopes instead of passing through raw controller responses.

### Fixed
- Added a launchd `PATH` to the controller LaunchAgent so runtime tools installed in `~/.local/bin`, Homebrew, and system locations can be found without per-profile overrides.
- Improved controller doctor findings for missing runtime executables with explicit `SERVER_BIN` remediation.
- Replaced generic profile action timeout errors in the app with action/profile-specific messages that include doctor diagnostics when available.

## [1.1.6] - 2026-05-17

### Added
- Added a terminal demo recording and refreshed screenshot assets for the README.

### Changed
- Redesigned the README hero and gallery around the current Base, Plus, benchmark, and controller workflows.
- Hardened controller profile parsing so `.env` profiles are treated as declarative key/value data instead of shell scripts, with explicit validation shared by the CLI and launcher.

### Fixed
- Preserved llama.cpp chat template arguments and launcher start timeouts when generating managed runtime commands.
- Removed a local filesystem path from the terminal demo source.

## [1.1.5] - 2026-05-02

### Fixed
- Verified Stop and Stop All results from the app after controller responses so lingering model processes are surfaced as errors instead of being hidden by optimistic UI state.

## [1.1.4] - 2026-05-02

### Fixed
- Kept the dashboard open after model action clicks so users can see profiles transition through starting, stopping, and running states.
- Hardened controller shutdown so Stop and Stop All terminate child processes, process groups, and stale profile port listeners instead of leaving model-serving Python processes resident.

## [1.1.3] - 2026-05-02

### Added
- Added active-profile recovery in the controller so an activated local model profile is restarted when its process and health check both disappear.

### Fixed
- Fixed overnight local-model runs silently staying down after an MLX or other managed runtime crash.

## [1.1.2] - 2026-04-26

### Added
- Added a release privacy audit that scans tracked source and built app bundles for local user paths, private-key material, and common token-shaped secret values.
- Added README coverage for supported runtimes, providers, external endpoints, and model-level runtime tags.

### Changed
- Release verification now runs the privacy audit against app bundles before publication, and the installer now installs from the same stripped build output used for distribution.

### Fixed
- Stripped Mach-O debug/source metadata before signing so public DMGs and locally installed apps do not retain local build paths.
- Removed a personal path from a controller test fixture.

## [1.1.1] - 2026-04-26

### Added
- Added first-class runtime labels and tags for current OpenAI-compatible local launchers including Mistral.rs, MLC-LLM, LightLLM, FastChat, OpenLLM, Nexa, MLX Omni Server, MLX Serve, LiteLLM, TensorRT-LLM, and ONNX Runtime GenAI.

### Fixed
- Added explicit dashboard edge resize handles so resizing works from the left side of the menu window as well as the right.
- Preferred local model directories and files before remote model IDs when a profile provides both, avoiding accidental network fetches for adapter-based launchers.
- Preserved runtime labels, tags, and launch mode through Swift status mutations so profile cards keep displaying the controller's real runtime metadata.

## [1.1.0] - 2026-04-25

### Added
- Added universal launcher support for local model profiles, including llama.cpp, MLX, vLLM, Ollama, OpenAI-compatible servers, custom commands, and runtime-specific metadata tags.
- Added a live RAM utilization badge between CPU and GPU telemetry in the Plus menu header.
- Added safe button-action stress coverage that can simulate 10,000 menu and inspector clicks without starting local models.

### Changed
- Moved controller-side install guidance and live-controller expectations toward the `~/AI/modelswitchboard` root with profile storage under `model-profiles`.
- Expanded release and setup documentation around runtime selection, launcher tags, downloaded-DMG setup, and managed controller paths.

### Fixed
- Hardened model lifecycle shutdown, launcher log alias sanitization, and Droid sync compatibility on Python 3.9.
- Stabilized installed-app verification against the migrated controller root and live Plus app expectations.

## [1.0.7] - 2026-04-24

### Added
- Added regression coverage for loopback endpoint fast-fail cadence, managed-action suppression, and remote-profile probe skipping.

### Changed
- Reworked the localhost fast-fail path to reuse a dedicated probe session, use a lightweight `HEAD` probe against the model base URL, and back off from a 2-second startup window to a steadier cadence over time.

### Fixed
- Dropped dead loopback model endpoints out of the UI faster without waiting for the next controller refresh tick.
- Avoided redundant localhost probe churn immediately after app-driven start, stop, restart, activate, and stop-all actions.

## [1.0.6] - 2026-04-23

### Added
- Added app regression coverage for fresh, stale, and cached controller snapshots so the menu bar state stays honest when localhost models stop out of band.

### Changed
- Kept controller auto-refresh running for the lifetime of the app instead of only while the menu is open.
- Tightened active-runtime refresh cadence from 30 seconds to 10 seconds and documented the always-resident lightweight polling model in `SETUP.md`.

### Fixed
- Stopped stale or cached localhost status from showing live running and ready counts in the menu bar.
- Marked stale running profiles as `STALE` instead of `RUNNING` until the next successful refresh, and updated the status-item tooltip to match.

## [1.0.5] - 2026-04-20

### Added
- Added `Scripts/bump-version.py` plus release-automation tests so version bumps update the repo consistently instead of hand-editing release files.

### Changed
- Updated `.github/workflows/release.yml` so a version bump pushed to `main` now builds, notarizes, and publishes the GitHub release automatically, while preserving manual and tag-driven releases.
- Documented the automated maintainer release flow in `README.md` and `SETUP.md`.

### Fixed
- Fixed local llama.cpp profile resolution so `MODEL_FILE` now works with `MODEL_ROOT_HINT`, `~/AI/models`, and `../models` fallbacks instead of requiring `MODEL_ROOT`.
- Passed through llama.cpp `CHAT_TEMPLATE_KWARGS` and `CACHE_RAM`, which restores Qwen no-think setups without forcing `RUNTIME=custom`.
- Added `--root` support to the controller installer so LaunchAgent installs can target any controller checkout without plist hand-edits.

## [1.0.4] - 2026-04-20

### Added
- Added controller doctor validation for duplicate profile endpoints so conflicting `HOST:PORT` or `BASE_URL` assignments are called out before activation.
- Added controller regression coverage for loopback endpoint normalization, conflict reporting, and activation refusal.

### Changed
- Documented the unique-endpoint requirement in the setup docs so profile authors do not accidentally point two models at the same listener.

### Fixed
- Blocked `Activate`, `Start`, and `Restart` when a profile shares an endpoint with another profile.
- Prevented conflicted profiles from borrowing the same port listener PID and appearing to co-activate in the UI.

## [1.0.3] - 2026-04-19

### Added
- Added a footer benchmark viewer shortcut in Plus so the latest benchmark panel can be reopened without rerunning a job.
- Added regression coverage for inspector close/reopen timing, benchmark timestamp parsing, profile display ordering, and controller benchmark result validation.

### Changed
- Sorted profile cards deterministically by live state first, then local endpoint order for inactive profiles, so the app no longer reshuffles idle models across refreshes.
- Reformatted benchmark timestamps into readable local date/time output instead of exposing raw ISO strings in the panel.

### Fixed
- Fixed the side-panel lifecycle so closing Benchmark, Settings, or Help no longer requires defocusing the app before reopening another panel.
- Reduced inspector close jitter by deferring host-window refocus until the panel hide transition has actually completed.
- Prevented empty benchmark streams from being scored as fake ultra-high throughput and attached the underlying non-stream error to failed benchmark results for diagnosis.

## [1.0.2] - 2026-04-17

### Added
- Added `Scripts/release-preflight.sh` to validate release prerequisites, version alignment, script wiring, tests, and build readiness.
- Added a documented manual release checklist item for login-item exclusivity when both editions are installed.

### Changed
- Updated `.github/workflows/release.yml` to use `actions/checkout@v5`.
- Replaced release upload via `softprops/action-gh-release` with `gh release` to avoid Node runtime churn and support idempotent re-runs.
- Hardened `Scripts/verify-installed-app.sh` with AppleScript retry behavior and optional headless fallback mode via `MSW_VERIFY_UI=0`.

### Fixed
- Reduced flaky menu opening and foreground-app automation failures in installed-app verification.

## [1.0.1] - 2026-04-17

### Fixed
- Fixed login-item conflict behavior between Base and Plus so enabling one unregisters the companion edition.
- Added login-item companion bundle mapping tests.
- Hardened release compatibility for CI and notarized distribution verification.

### Security
- Added ignore patterns for local key artifacts (`*.p8`, `*.p12`, `*.pem`, `*.key`, `*.cer`, `*.crt`) and environment files.

## [1.0.0] - 2026-04-17

### Added
- Initial public release with Base and Plus editions.
- Signed/notarized DMG release pipeline.
- Controller contract, runtime adapters, benchmark flows, and docs.
