# Changelog

All notable changes to this project are documented in this file.

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
