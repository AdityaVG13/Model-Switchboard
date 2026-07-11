# Controller API Conformance Fixture Provenance

- **Fixture:** `controller_api_cases.json`
- **Golden artifact:** `../REPORT.md`
- **Specification source:** repository-local controller API contract
- **Pinned source files:**
  - `Sources/ModelSwitchboardControllerCore/ControllerRouter.swift`
  - `Sources/ModelSwitchboardControllerCore/HTTPServer.swift`
  - `Sources/ModelSwitchboardCore/ControllerClient.swift`
- **Generated:** 2026-07-11
- **Generator:** hand-authored from the repository contract and validated by `ModelSwitchboardControllerTests`
- **Regeneration workflow:**
  1. Update `controller_api_cases.json` when the controller API contract changes.
  2. Run `swift test --filter ModelSwitchboardControllerTests`.
  3. Review `git diff Controller/tests/conformance/` before committing.

No external reference implementation is used. The contract is the observable HTTP behavior shared by the native Swift controller and Swift client.
