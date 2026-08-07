# Pass 01 -- Listening-TCP inventory cache policy

**Lever (one):** raise `LISTENING_TCP_CACHE_TTL_SECONDS` from `0.075` to `2.0`.

**File:** `RemoteAgent/model_switchboard_agent.py` only.

**Source profile:** `Tests/artifacts/perf/20260803_remote-gateway-profiling/` -- list_listening_tcp cache miss → `lsof` on macOS dominates `status_payload` p95 (~45–57ms). Old 75ms TTL was shorter than any real UI poll (~10s active refresh), so almost every poll cold-missed.

---

## Mechanism

| Before | After |
|--------|--------|
| Cache hit only if age < 75ms | Cache hit if age < 2.0s |
| Same lock, same fill-on-miss, same `_copy_listening_tcp_rows` | Unchanged |
| Concurrent misses still coalesce under `_listening_tcp_cache_lock` | Unchanged |

No soft-stale dual-threshold: a single hard TTL of 2.0s is the isomorphic policy change (return last snapshot while age < TTL; force `_list_listening_tcp_uncached` when older). Soft-stale with soft==hard collapses to the same control plane; dual soft/hard would add paths without changing the documented lag bound for this pass.

---

## Invariants preserved

| Invariant | How |
|-----------|-----|
| **Inventory row shape** | Same `_list_listening_tcp_uncached` builders; cache stores/returns identical `dict` keys (`port`, `pid`, `command`, `bind`, …). |
| **Private copies for callers** | Still `_copy_listening_tcp_rows` on every hit and miss return; mutation isolation tests unchanged. |
| **Ports / status semantics within lag bound** | Listen/port presence may lag **≤ 2.0s** (was ≤ 75ms). Documented on the constant and `list_listening_tcp` docstring. UI status refresh ~10s; 2s covers rapid re-polls, multi-client bursts, and concurrent status/ports/scan callers. |
| **Live accuracy where required** | `stop`/`start` keep `listener_pid()` (not inventory-only). `clear_listening_tcp_cache()` still forces refill. |
| **Per-request single inventory** | `status_payload` still one `list_listening_tcp()` per request; win is **cross-request** reuse. |
| **Thread safety** | Lock held across fill; no stampede / DCL race with clear mid-write. |

---

## Explicitly out of scope (this pass)

- Parallelize `pollOnce`
- Change `profile_statuses` probes
- Optimize `host_metrics`
- Background soft-refresh while serving stale

---

## Expected effect

- Miss rate for callers within 2s of a prior inventory → ~0 (was ~100% for any spacing >75ms).
- On cache hit: avoid full `lsof`/`ss`/`proc` inventory (~45–57ms macOS p95 contribution on miss).
- On 10s-spaced UI polls alone: still a miss each tick if spacing >2s; still wins when handlers/clients re-enter sooner or when multiple endpoints inventory in the same window.

---

## Verification

- Unit: superseded by `swift test --filter RemoteAgentConformanceTests` (Python suite removed)
- Tests already advance clock via `LISTENING_TCP_CACHE_TTL_SECONDS + 0.001` for expiry; within-TTL uses +0.05s (still < 2.0).
