# Changelog

All notable changes to this project are documented in this file.

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
