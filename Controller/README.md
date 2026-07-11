# ModelSwitchboard Controller

The production control plane is a native Swift service. Its implementation lives in `Sources/ModelSwitchboardControllerCore/`; the executable entrypoint is `Sources/ModelSwitchboardController/`.

## Runtime assets

- `start-model-mac.sh` launches profile-backed model servers.
- `stop-all-models.sh` safely stops tracked model processes.
- `model-profiles/` contains user profiles and examples.
- `swiftbar/local-models.15s.sh` exposes the same controller through SwiftBar.

The Swift controller owns profile parsing, status and health probes, lifecycle serialization, authentication, doctor diagnostics, Factory Droid sync, benchmark orchestration, status caching, and the `/api/*` HTTP service.

## Native CLI

Build once:

```bash
swift build -c release --product ModelSwitchboardController
```

Run against this controller root:

```bash
CONTROLLER="$(swift build -c release --show-bin-path)/ModelSwitchboardController"
$CONTROLLER triage --root Controller
$CONTROLLER capabilities --root Controller
$CONTROLLER status --root Controller
$CONTROLLER start <profile> --root Controller
$CONTROLLER stop <profile> --root Controller
$CONTROLLER restart <profile> --root Controller
$CONTROLLER switch <profile> --root Controller
$CONTROLLER stop-all --root Controller
$CONTROLLER doctor --root Controller
$CONTROLLER doctor health --root Controller
$CONTROLLER doctor --fix --dry-run --root Controller
$CONTROLLER benchmark --suite quick --root Controller
$CONTROLLER serve --root Controller
```

## Installation

Distributed app builds embed the signed controller binary, runtime assets, and LaunchAgent property list. The app registers the agent with `SMAppService` and seeds runtime assets under:

```text
~/Library/Application Support/ModelSwitchboard/Controller
```

Source checkouts can install the same native service directly:

```bash
./Controller/install-model-switchboard-controller.sh
```

No Python runtime is required by the controller or its tests.

## Tests

```bash
swift test --filter ModelSwitchboardControllerTests
```

Coverage includes profile parsing, endpoint conflicts, lifecycle actions, authentication, request validation, status and doctor contracts, integrations, benchmarks, and a real loopback HTTP listener.
