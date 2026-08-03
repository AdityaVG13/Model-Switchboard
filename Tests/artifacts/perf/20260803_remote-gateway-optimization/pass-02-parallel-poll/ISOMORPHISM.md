# Pass 02 -- Parallelize `RemoteHostMetricsMonitor.pollOnce`

**Lever (one):** concurrent per-gateway host-metrics fetches inside `pollOnce`.

**File:** `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift` (tests: `Tests/ModelSwitchboardAppTests/RemoteHostMetricsMonitorTests.swift`).

**Source profile:** Sequential `for runtime in runtimes { await fetch(...) }` on MainActor. For N remotes with RTT R and server work S, wall ≈ Σ(Rᵢ+Sᵢ). With N≥2 remotes this dominates the 3s poll budget and stretches UI freshness.

---

## Mechanism

| Before | After |
|--------|--------|
| Sequential `await fetch(runtime:)` per enabled remote | Snapshot MainActor state → `withTaskGroup` concurrent `resolveEntry` → merge into `entries` on MainActor |
| Network + entry mutation interleaved on MainActor | Network off critical path via `nonisolated static resolveEntry` + Sendable `ControllerClient` / `Entry` |
| Wall ≈ N × (RTT + server) | Wall ≈ max(RTT + server) + small snapshot/merge |

No change to:

- Default poll interval (`intervalSeconds = 3`)
- HTTP path (`GET /api/host/metrics` via `ControllerClient.fetchHostMetrics`)
- Entry shape / unsupported-message copy
- Stale-metrics-on-error behavior

### Snapshot → fan-out → merge

1. **MainActor snapshot:** for each `enabledRemoteRuntime`, capture `(id, previous Entry, ControllerClient? or immediateError)`.
2. **Task group:** each child runs `resolveEntry` without `@MainActor in` (avoids Swift 6 region-based isolation errors).
3. **MainActor merge:** assign `entries[id] = entry` for all results.

Tunnel-not-ready and client-build failures are immediate targets (no HTTP); tunnel path still omits `updatedAt` stamp (`preserveUpdatedAt: true`).

---

## Invariants preserved

| Invariant | How |
|-----------|-----|
| **Per-gateway error isolation** | One failing child returns its own `(id, Entry)`; others still complete. Covered by unit test. |
| **Last-good metrics on transient failure** | Catch path mutates a copy of `previous`, keeps `metrics`. Covered by unit test. |
| **Unsupported agents (404 / not found)** | Same message detection and redeploy copy. |
| **SSH tunnel gate** | Tunnel check still before HTTP; error-only update, no `updatedAt` stamp. |
| **Removed gateway cleanup** | Still drop `entries` keys not in active set before fetch. |
| **MainActor observation surface** | `entries` only written on MainActor after group completes. |
| **Poll interval / API** | Unchanged defaults and wire protocol. |

---

## Explicitly out of scope (this pass)

- Agent-side inventory / listening-TCP cache (pass 01)
- Changing `profile_statuses` or store refresh concurrency
- Adaptive poll interval or cancel-in-flight coalescing
- Shared URLSession pool tuning

---

## Expected effect

- N remotes: poll wall time drops from ~N·R toward ~max(R) (network-bound case).
- Single remote: ~same cost (task group overhead negligible vs RTT).
- UI host metrics for multiple remotes refresh within one interval instead of cascading.

---

## Verification

```bash
swift test --filter 'GatewayHubTests|HostMetrics|RemoteHostMetricsMonitor'
```

Unit coverage:

- `pollOnceIsolatesErrorsAcrossConcurrentGateways` -- one 200 + one 404 → success entry and unsupported entry both present.
- `pollOncePreservesLastGoodMetricsOnTransientFailure` -- 200 then 503 keeps prior metrics.
