# Controller Real-Service E2E

These tests start the native Swift HTTP listener and exercise its API over loopback. They do not patch controller behavior.

## Mock Risk Matrix

| Code Path | Production Impact | Mock Divergence Risk | Last Bug from Mock | Score |
|---|---:|---:|---|---:|
| Native controller HTTP status/auth/cache flow | 3 | 3 | N/A | 9 |

Score 9 requires mock-free coverage. The controller process owns authentication, request routing, profile discovery, watchdog startup, and status-cache writes; an in-process mocked handler can miss process/env/path behavior.

## Harness Rules

- Starts `ControllerHTTPServer` with an isolated temporary controller root.
- Uses `127.0.0.1` and blocks non-local URLs.
- Cancels the native listener after each test.

Run:

```bash
swift test --filter nativeHTTPServerPassesRealServiceE2E
```
