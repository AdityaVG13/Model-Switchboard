# Controller Real-Service E2E

These tests start the real Python controller process and exercise its HTTP API over loopback. They do not patch controller functions or replace the service with an in-process handler.

## Mock Risk Matrix

| Code Path | Production Impact | Mock Divergence Risk | Last Bug from Mock | Score |
|---|---:|---:|---|---:|
| `modelctl.py serve-web` HTTP status/auth/cache flow | 3 | 3 | N/A | 9 |

Score 9 requires mock-free coverage. The controller process owns authentication, request routing, profile discovery, watchdog startup, and status-cache writes; an in-process mocked handler can miss process/env/path behavior.

## Harness Rules

- Starts `modelctl.py serve-web` as a subprocess.
- Uses a temp `HOME` so cache and LaunchAgent paths never touch the user's real home.
- Uses `127.0.0.1` and blocks non-local URLs.
- Emits JSON-line phase logs to stderr.
- Tears down the process group after each test.
- No DB transaction wrapper is needed; this repo has no database service. Temp-home isolation covers the real filesystem writes used by this controller path.

Run:

```bash
uv run python3 -m unittest Controller.tests.test_controller_real_service_e2e
```
