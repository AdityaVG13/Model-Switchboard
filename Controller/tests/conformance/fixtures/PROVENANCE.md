# Controller API Conformance Fixture Provenance

- **Fixture:** `controller_api_cases.json`
- **Golden artifact:** `../REPORT.md`
- **Specification source:** repository-local controller API contract
- **Pinned source files:**
  - `Controller/modelctl.py`
  - `Controller/contracts.py`
  - `Sources/ModelSwitchboardCore/ControllerClient.swift`
- **Generated:** 2026-05-17
- **Generator:** hand-authored from the repository contract and validated by `Controller/tests/test_controller_conformance.py`
- **Regeneration workflow:**
  1. Update `controller_api_cases.json` when the controller API contract changes.
  2. Run `uv run python3 -m unittest Controller.tests.test_controller_conformance`.
  3. Run with `UPDATE_GOLDENS=1` only when the fixture or report change is intentional.
  4. Review `git diff Controller/tests/conformance/` before committing.

Golden comparison canonicalizes line endings, path separators, and local home directories. On mismatch the harness writes `*.actual` files for diff review; those transient files are gitignored.

No external reference implementation is used for this harness. The contract is the observable HTTP behavior shared by the Python controller and Swift client.
