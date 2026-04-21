# Changelog

All notable changes to this project are documented in this file.

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
